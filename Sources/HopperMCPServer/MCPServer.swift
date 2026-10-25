import Foundation

struct RPCFailure: Error {
    let code: Int
    let message: String
}

final class MCPServer {
    private enum State { case created, initializing, ready }
    private var state = State.created
    private var protocolVersion = "2025-03-26"
    private let bridge: BridgeClient
    private let catalog: ToolCatalog

    init(bridge: BridgeClient, catalog: ToolCatalog) {
        self.bridge = bridge
        self.catalog = catalog
    }

    func run() throws {
        let reader = LineReader(input: .standardInput)
        while let line = try reader.next() {
            if line.isEmpty { continue }
            let message: Any
            do { message = try JSONSerialization.jsonObject(with: line, options: .fragmentsAllowed) }
            catch { try send(failure(code: -32700, message: "Invalid JSON", identifier: NSNull())); continue }
            if let batch = message as? [Any] {
                guard !batch.isEmpty, ["2024-11-05", "2025-03-26"].contains(protocolVersion) else {
                    try send(failure(code: -32600, message: "JSON-RPC batches are unavailable for this protocol version", identifier: NSNull()))
                    continue
                }
                let responses = batch.compactMap { element -> [String: Any]? in
                    if let request = element as? [String: Any], request["method"] as? String == "initialize" {
                        return failure(code: -32600, message: "initialize must be sent individually", identifier: request["id"] ?? NSNull())
                    }
                    return process(element)
                }
                if !responses.isEmpty { try send(responses) }
            } else if let response = process(message) { try send(response) }
        }
    }

    private func process(_ value: Any) -> [String: Any]? {
        guard let request = value as? [String: Any], request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return failure(code: -32600, message: "Expected a JSON-RPC 2.0 request", identifier: NSNull())
        }
        guard let identifier = request["id"] else {
            if method == "notifications/initialized", state == .initializing { state = .ready }
            return nil
        }
        guard identifier is String || identifier is NSNumber || identifier is NSNull else {
            return failure(code: -32600, message: "Invalid request identifier", identifier: NSNull())
        }
        if let number = identifier as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return failure(code: -32600, message: "Boolean request identifiers are invalid", identifier: NSNull())
        }
        do {
            guard request["params"] == nil || request["params"] is [String: Any] else { throw RPCFailure(code: -32602, message: "params must be an object") }
            let parameters = request["params"] as? [String: Any] ?? [:]
            let result: Any
            switch method {
            case "initialize":
                guard state == .created else { throw RPCFailure(code: -32600, message: "The connection is already initialized") }
                guard let requested = parameters["protocolVersion"] as? String else { throw RPCFailure(code: -32602, message: "protocolVersion is required") }
                guard parameters["capabilities"] is [String: Any], let client = parameters["clientInfo"] as? [String: Any],
                      client["name"] is String, client["version"] is String else {
                    throw RPCFailure(code: -32602, message: "capabilities and clientInfo (name, version) are required")
                }
                let supported = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
                protocolVersion = supported.contains(requested) ? requested : "2025-11-25"
                state = .initializing
                result = ["protocolVersion": protocolVersion, "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "HopperMCPServer", "version": "1.0.0"],
                    "instructions": "Use list_documents and pass an explicit document. Queries preserve application focus. Discover further native APIs with get_object, list_api, invoke_api and api_documentation. set_current_document selects the MCP default only. The bridge is a Hopper Tool Plugin; no companion application or privileged helper is required."]
            case "ping": result = [:] as [String: Any]
            case "tools/list":
                try requireReady()
                if parameters["cursor"] != nil { throw RPCFailure(code: -32602, message: "The static catalog has no continuation cursor") }
                result = ["tools": catalog.tools]
            case "tools/call":
                try requireReady()
                guard let name = parameters["name"] as? String, parameters["arguments"] == nil || parameters["arguments"] is [String: Any] else {
                    throw RPCFailure(code: -32602, message: "Expected a tool name and arguments object")
                }
                let arguments = parameters["arguments"] as? [String: Any] ?? [:]
                try catalog.validate(name: name, arguments: arguments)
                do {
                    let value = try name == "api_documentation" ? catalog.documentation(arguments: arguments) : bridge.call(name: name, arguments: arguments)
                    let text: String
                    if let string = value as? String { text = string }
                    else { text = String(data: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)! }
                    result = ["content": [["type": "text", "text": text]], "isError": false]
                } catch {
                    result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
                }
            default: throw RPCFailure(code: -32601, message: "Unknown method: \(method)")
            }
            return ["jsonrpc": "2.0", "id": identifier, "result": result]
        } catch let error as RPCFailure {
            return failure(code: error.code, message: error.message, identifier: identifier)
        } catch {
            return failure(code: -32603, message: error.localizedDescription, identifier: identifier)
        }
    }

    private func requireReady() throws {
        guard state == .ready else { throw RPCFailure(code: -32002, message: "Initialize the connection and send notifications/initialized first") }
    }

    private func failure(code: Int, message: String, identifier: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": identifier, "error": ["code": code, "message": message]]
    }

    private func send(_ message: Any) throws {
        var output = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed, .sortedKeys])
        output.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: output)
    }
}
