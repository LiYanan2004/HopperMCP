import Darwin
import Foundation

do {
    var configuration = BridgeConfiguration()
    var operation: String?
    var pluginSource: URL?
    var arguments: [String: Any] = [:]
    var input = Array(CommandLine.arguments.dropFirst()).makeIterator()
    while let flag = input.next() {
        switch flag {
        case "--app-path":
            guard let path = input.next(), path.hasPrefix("/") else { throw BridgeFailure.operation("--app-path requires an absolute application path") }
            configuration.applicationPath = path
        case "--pid":
            guard let value = input.next(), let identifier = Int32(value), identifier > 0 else { throw BridgeFailure.operation("--pid requires a positive process identifier") }
            configuration.processIdentifier = identifier
        case "--timeout":
            guard let value = input.next(), let seconds = Int(value), (1...3600).contains(seconds) else { throw BridgeFailure.operation("--timeout requires 1 to 3600 seconds") }
            configuration.timeoutSeconds = seconds
        case "--status": operation = "bridge_status"
        case "--install-plugin":
            guard let path = input.next() else { throw BridgeFailure.operation("--install-plugin requires the plugin bundle path") }
            pluginSource = URL(fileURLWithPath: path)
        case "--call":
            guard let name = input.next() else { throw BridgeFailure.operation("--call requires a tool name") }
            operation = name
        case "--arguments":
            guard let value = input.next(), let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else { throw BridgeFailure.operation("--arguments requires a JSON object") }
            arguments = object
        case "--help":
            print("HopperMCPServer [--app-path PATH] [--pid PID] [--timeout SECONDS]\nHopperMCPServer --install-plugin PATH\nHopperMCPServer --status\nHopperMCPServer --call TOOL --arguments JSON\nBy default, the server discovers a running Hopper bridge. Use --app-path or --pid to select among several processes.\nWithout a diagnostic operation, the server speaks MCP over standard input/output.")
            exit(0)
        default: throw BridgeFailure.operation("Unknown option: \(flag)")
        }
    }
    if let pluginSource {
        let destination = try PluginInstaller().install(from: pluginSource)
        print("Installed \(destination.path)\nRestart Hopper to load the installed version.")
        exit(0)
    }
    let bridge = BridgeClient(configuration: configuration)
    defer { bridge.close() }
    let catalog = try ToolCatalog()
    if let operation {
        try catalog.validate(name: operation, arguments: arguments)
        let result = try operation == "api_documentation" ? catalog.documentation(arguments: arguments) : bridge.call(name: operation, arguments: arguments)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    } else {
        try MCPServer(bridge: bridge, catalog: catalog).run()
    }
} catch {
    let message = (error as? RPCFailure).map(\.message) ?? error.localizedDescription
    FileHandle.standardError.write(Data(("HopperMCPServer: " + message + "\n").utf8))
    exit(1)
}
