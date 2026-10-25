import Darwin
import Foundation

struct PluginInstaller {
    func install(from source: URL) throws -> URL {
        let fileManager = FileManager.default
        let identifier = "io.hopper-mcp.bridge"
        guard let metadata = try PropertyListSerialization.propertyList(from: Data(contentsOf: source.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              metadata["CFBundleIdentifier"] as? String == identifier else {
            throw BridgeFailure.operation("Select the HopperMCPBridge.hopperTool bundle distributed with this server")
        }
        let directory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Hopper/PlugIns/v4/Tools", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".hopper-mcp-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        let entries = [temporary] + (fileManager.enumerator(at: temporary, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? [])
        for entry in entries {
            guard (try entry.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
                throw BridgeFailure.operation("The plugin bundle must contain ordinary files and directories")
            }
            for attribute in ["com.apple.FinderInfo", "com.apple.ResourceFork"] {
                _ = removexattr(entry.path, attribute, 0)
            }
        }
        let verification = Process()
        verification.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verification.arguments = ["--verify", "--strict", temporary.path]
        let diagnostics = Pipe()
        verification.standardError = diagnostics
        try verification.run()
        let output = diagnostics.fileHandleForReading.readDataToEndOfFile()
        verification.waitUntilExit()
        guard verification.terminationStatus == 0 else {
            throw BridgeFailure.operation("Plugin signature verification failed: \(String(data: output, encoding: .utf8) ?? "unknown error")")
        }
        let destination = directory.appendingPathComponent("HopperMCPBridge.hopperTool", isDirectory: true)
        let backupDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HopperMCP/Backups", isDirectory: true)
        var backup: URL?
        if fileManager.fileExists(atPath: destination.path) {
            let installedMetadata = try PropertyListSerialization.propertyList(from: Data(contentsOf: destination.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
            guard installedMetadata?["CFBundleIdentifier"] as? String == identifier else {
                throw BridgeFailure.operation("The destination belongs to another plugin")
            }
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let previous = backupDirectory.appendingPathComponent("HopperMCPBridge-\(UUID().uuidString).hopperTool", isDirectory: true)
            try fileManager.moveItem(at: destination, to: previous)
            backup = previous
        }
        do { try fileManager.moveItem(at: temporary, to: destination) }
        catch {
            if let backup { try? fileManager.moveItem(at: backup, to: destination) }
            throw error
        }
        return destination
    }
}
