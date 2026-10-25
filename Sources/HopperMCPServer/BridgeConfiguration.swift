import Foundation

struct BridgeConfiguration {
    var applicationPath: String?
    var processIdentifier: Int32?
    var timeoutSeconds: Int = 120

    var runtimeDirectory: URL {
        URL(fileURLWithPath: "/tmp/hopper-mcp-\(getuid())", isDirectory: true)
    }
}

enum BridgeFailure: LocalizedError {
    case unavailable(String)
    case invalidResponse(String)
    case operation(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .invalidResponse(message), let .operation(message): message
        }
    }
}
