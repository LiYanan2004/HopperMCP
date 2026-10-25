import Darwin
import Foundation

final class BridgeClient {
    private let configuration: BridgeConfiguration
    private let maximumMessageLength = 32 * 1024 * 1024
    private let sessionIdentifier = UUID().uuidString

    init(configuration: BridgeConfiguration) {
        self.configuration = configuration
    }

    func call(name: String, arguments: [String: Any]) throws -> Any {
        try performRequest(name: name, arguments: arguments, awaitReply: true)
    }

    func close() {
        _ = try? performRequest(name: "release_session", arguments: [:], awaitReply: false)
    }

    private func performRequest(name: String, arguments: [String: Any], awaitReply: Bool) throws -> Any {
        let endpoint = try discoverEndpoint()
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw systemFailure("Create bridge connection") }
        defer { Darwin.close(descriptor) }

        var timeout = timeval(tv_sec: awaitReply ? configuration.timeoutSeconds : 1, tv_usec: 0)
        var suppressSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &suppressSignal, socklen_t(MemoryLayout.size(ofValue: suppressSignal))) == 0 else {
            throw systemFailure("Configure bridge connection")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(endpoint.socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw BridgeFailure.unavailable("The bridge socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw systemFailure("Connect to Hopper; restart Hopper after installing the plugin") }

        var request = try JSONSerialization.data(withJSONObject: ["method": "call", "name": name, "arguments": arguments, "client": sessionIdentifier])
        guard request.count < maximumMessageLength else { throw BridgeFailure.operation("The request exceeds 32 MiB") }
        request.append(0x0A)
        try request.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw systemFailure("Send bridge request") }
                offset += count
            }
        }
        if !awaitReply { return NSNull() }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !response.contains(0x0A) {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                if count == 0 { throw BridgeFailure.invalidResponse("Hopper closed the connection without a complete reply") }
                throw systemFailure("Receive bridge reply")
            }
            response.append(contentsOf: buffer.prefix(count))
            guard response.count <= maximumMessageLength else {
                throw BridgeFailure.invalidResponse("The reply exceeds 32 MiB; narrow the query")
            }
        }
        guard let message = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw BridgeFailure.invalidResponse("Expected a bridge response object")
        }
        if let error = message["error"] as? [String: Any] {
            throw BridgeFailure.operation(error["message"] as? String ?? "Hopper operation failed")
        }
        guard let result = message["result"] else {
            throw BridgeFailure.invalidResponse("The bridge reply has no result")
        }
        return result
    }

    private struct Endpoint: Decodable {
        let pid: Int32
        let socketPath: String
        let bundlePath: String
        let protocolVersion: Int

        enum CodingKeys: String, CodingKey {
            case pid
            case socketPath = "socket"
            case bundlePath = "bundle_path"
            case protocolVersion = "protocol_version"
        }
    }

    private func discoverEndpoint() throws -> Endpoint {
        let directory = configuration.runtimeDirectory
        var directoryInformation = stat()
        guard lstat(directory.path, &directoryInformation) == 0,
              directoryInformation.st_uid == getuid(),
              directoryInformation.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryInformation.st_mode & 0o077 == 0 else {
            throw BridgeFailure.unavailable("No private Hopper bridge directory. Start Hopper with HopperMCPBridge.hopperTool installed")
        }
        let paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        let application = configuration.applicationPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        var candidates: [Endpoint] = []
        for path in paths where path.pathExtension == "json" {
            guard (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = try? Data(contentsOf: path), data.count < 8192,
                  let endpoint = try? JSONDecoder().decode(Endpoint.self, from: data),
                  endpoint.protocolVersion == 1,
                  endpoint.pid > 0, Darwin.kill(endpoint.pid, 0) == 0,
                  application == nil || URL(fileURLWithPath: endpoint.bundlePath).standardizedFileURL.path == application,
                  endpoint.socketPath == directory.appendingPathComponent("\(endpoint.pid).sock").path,
                  configuration.processIdentifier == nil || configuration.processIdentifier == endpoint.pid else { continue }
            var socketInformation = stat()
            guard lstat(endpoint.socketPath, &socketInformation) == 0,
                  socketInformation.st_uid == getuid(),
                  socketInformation.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else { continue }
            candidates.append(endpoint)
        }
        guard candidates.count == 1 else {
            if candidates.isEmpty {
                let target = application.map { " for \($0)" } ?? ""
                throw BridgeFailure.unavailable("No live Hopper bridge\(target). Start Hopper after installing its plugin")
            }
            throw BridgeFailure.unavailable("Several Hopper processes match; select one with --pid or --app-path")
        }
        return candidates[0]
    }

    private func systemFailure(_ action: String) -> BridgeFailure {
        .unavailable("\(action): \(String(cString: strerror(errno)))")
    }
}
