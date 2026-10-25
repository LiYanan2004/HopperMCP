import Darwin
import Foundation

final class LineReader {
    private let input: FileHandle
    private var pending = Data()
    private let maximumLength = 32 * 1024 * 1024

    init(input: FileHandle) {
        self.input = input
    }

    func next() throws -> Data? {
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                guard pending.distance(from: pending.startIndex, to: newline) <= maximumLength else { throw BridgeFailure.operation("The JSON-RPC line exceeds 32 MiB") }
                let result = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                return result
            }
            guard pending.count <= maximumLength else { throw BridgeFailure.operation("The JSON-RPC line exceeds 32 MiB") }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = Darwin.read(input.fileDescriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count < 0 { throw BridgeFailure.operation("Read standard input: \(String(cString: strerror(errno)))") }
            guard count > 0 else {
                guard !pending.isEmpty else { return nil }
                defer { pending.removeAll() }
                return pending
            }
            pending.append(contentsOf: buffer.prefix(count))
        }
    }
}
