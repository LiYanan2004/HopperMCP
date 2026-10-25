import Foundation

@objc(HopperBridgePlugin)
final class HopperBridgePlugin: NSObject, HopperTool {
    private let services: HPHopperServices
    private let bridgeServer: HBBridgeServer
    private weak var toolPluginsMenuItem: NSObject?

    // Keep notification names local because Hopper 5 rejects AppKit global symbol bindings.
    private static let launchNotification = Notification.Name("NSApplicationDidFinishLaunchingNotification")
    private static let menuItemAddedNotification = Notification.Name("NSMenuDidAddItemNotification")
    private static let menuItemRemovedNotification = Notification.Name("NSMenuDidRemoveItemNotification")

    static func sdkVersion() -> Int32 {
        Int32(HBHopperSDKVersion)
    }
    
    func pluginType() -> HopperPluginType {
        .Plugin_Tool
    }
    
    func pluginUUID() -> HPHopperUUID {
        ervices.uuid(with: "BD330D85-FD77-41D8-954D-BB0658D21D51")
    }
    
    func pluginName() -> String {
        "Hopper MCP Bridge"
    }
    
    func pluginDescription() -> String {
        "Background bridge for an independent MCP server"
    }
    
    func pluginAuthor() -> String {
        "Hopper MCP Bridge contributors"
    }
    
    func pluginCopyright() -> String {
        "Copyright 2026 Hopper MCP Bridge contributors"
    }
    
    func pluginVersion() -> String {
        "1.0.0"
    }
    
    func commandLineIdentifiers() -> [String] {
        ["HopperMCPBridge"]
    }

    // Hopper initializes plugins on its main thread; deferred work and menu notifications use that same thread.
    required init(hopperServices services: HPHopperServices) {
        self.services = services
        bridgeServer = HBBridgeServer(services: services)
        super.init()
        bridgeServer.start()
        let applicationClass = NSClassFromString("NSApplication") as? NSObject.Type
        NotificationCenter.default.addObserver(self, selector: #selector(configureToolPluginsMenuVisibility(_:)),
                                               name: Self.launchNotification, object: applicationClass?.sharedApplication())
        perform(#selector(configureToolPluginsMenuVisibility(_:)), with: nil, afterDelay: 0)
    }

    // Keep the bridge running in the background without adding menu commands.
    func toolMenuDescription() -> [[String: Any]] { [] }

    // Observe the Tool Plugins submenu through runtime AppKit access compatible with Hopper 5.
    @objc private func configureToolPluginsMenuVisibility(_ notification: Notification?) {
        let applicationClass = NSClassFromString("NSApplication") as? NSObject.Type
        guard let menuItem = applicationClass?.sharedApplication()?.mainMenu()?.item(withTitle: "Tool Plugins"),
              let submenu = menuItem.submenu() else { return }
        if toolPluginsMenuItem !== menuItem {
            let notificationCenter = NotificationCenter.default
            if let previousMenu = toolPluginsMenuItem?.submenu() {
                notificationCenter.removeObserver(self, name: Self.menuItemAddedNotification, object: previousMenu)
                notificationCenter.removeObserver(self, name: Self.menuItemRemovedNotification, object: previousMenu)
            }
            toolPluginsMenuItem = menuItem
            notificationCenter.addObserver(self, selector: #selector(updateToolPluginsMenuVisibility(_:)),
                                           name: Self.menuItemAddedNotification, object: submenu)
            notificationCenter.addObserver(self, selector: #selector(updateToolPluginsMenuVisibility(_:)),
                                           name: Self.menuItemRemovedNotification, object: submenu)
        }
        updateToolPluginsMenuVisibility(nil)
    }

    // Hide Hopper's Tool Plugins menu while it is empty and show it when other plugins provide commands.
    @objc private func updateToolPluginsMenuVisibility(_ notification: Notification?) {
        guard let menuItem = toolPluginsMenuItem else { return }
        menuItem.setHidden(menuItem.submenu()?.numberOfItems() == 0)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
