#import <AppKit/AppKit.h>
#import "HopperTool.h"
#import "HPHopperServices.h"
#import "HBBridgeServer.h"

// Use notification names directly to avoid AppKit global symbol bindings in Hopper's plugin loader.
static NSNotificationName const HBApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
static NSNotificationName const HBMenuDidAddItemNotification = @"NSMenuDidAddItemNotification";
static NSNotificationName const HBMenuDidRemoveItemNotification = @"NSMenuDidRemoveItemNotification";

@interface HopperBridgePlugin : NSObject <HopperTool>
@property(nonatomic, strong) NSObject<HPHopperServices> *services;
@property(nonatomic, strong) HBBridgeServer *bridgeServer;
@property(nonatomic, weak) NSMenuItem *toolPluginsMenuItem;
@end

@implementation HopperBridgePlugin
#ifndef HB_HOPPER_SDK_VERSION
#define HB_HOPPER_SDK_VERSION 4
#endif
+ (int)sdkVersion { return HB_HOPPER_SDK_VERSION; }
- (HopperPluginType)pluginType { return Plugin_Tool; }
- (NSObject<HPHopperUUID> *)pluginUUID {
    return [self.services UUIDWithString:@"BD330D85-FD77-41D8-954D-BB0658D21D51"];
}
- (NSString *)pluginName { return @"Hopper MCP Bridge"; }
- (NSString *)pluginDescription { return @"Background bridge for an independent MCP server"; }
- (NSString *)pluginAuthor { return @"Hopper MCP Bridge contributors"; }
- (NSString *)pluginCopyright { return @"Copyright 2026 Hopper MCP Bridge contributors"; }
- (NSString *)pluginVersion { return @"1.0.0"; }
- (NSArray<NSString *> *)commandLineIdentifiers { return @[@"HopperMCPBridge"]; }
- (instancetype)initWithHopperServices:(NSObject<HPHopperServices> *)services {
    self = [super init];
    if (self) {
        self.services = services;
        self.bridgeServer = [[HBBridgeServer alloc] initWithServices:services];
        [self.bridgeServer start];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                selector:@selector(configureToolPluginsMenuVisibility:)
                                                    name:HBApplicationDidFinishLaunchingNotification
                                                  object:[NSClassFromString(@"NSApplication") sharedApplication]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureToolPluginsMenuVisibility:nil];
        });
    }
    return self;
}
// Keep the bridge running in the background without adding menu commands.
- (NSArray<NSDictionary<NSString *, id> *> *)toolMenuDescription {
    return @[];
}
// Observe the Tool Plugins submenu so its visibility follows commands added or removed by other plugins.
- (void)configureToolPluginsMenuVisibility:(NSNotification *)notification {
    (void)notification;
    NSApplication *application = [NSClassFromString(@"NSApplication") sharedApplication];
    NSMenuItem *menuItem = [application.mainMenu itemWithTitle:@"Tool Plugins"];
    if (menuItem == nil || menuItem.submenu == nil) return;
    if (self.toolPluginsMenuItem != menuItem) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSMenu *previousMenu = self.toolPluginsMenuItem.submenu;
        if (previousMenu != nil) {
            [notificationCenter removeObserver:self name:HBMenuDidAddItemNotification object:previousMenu];
            [notificationCenter removeObserver:self name:HBMenuDidRemoveItemNotification object:previousMenu];
        }
        self.toolPluginsMenuItem = menuItem;
        [notificationCenter addObserver:self selector:@selector(updateToolPluginsMenuVisibility:)
                                   name:HBMenuDidAddItemNotification object:menuItem.submenu];
        [notificationCenter addObserver:self selector:@selector(updateToolPluginsMenuVisibility:)
                                   name:HBMenuDidRemoveItemNotification object:menuItem.submenu];
    }
    [self updateToolPluginsMenuVisibility:nil];
}
// Hide Hopper's Tool Plugins menu while it is empty and show it when other plugins provide commands.
- (void)updateToolPluginsMenuVisibility:(NSNotification *)notification {
    (void)notification;
    NSMenuItem *menuItem = self.toolPluginsMenuItem;
    menuItem.hidden = menuItem.submenu.numberOfItems == 0;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)showBridgeStatus:(id)sender {
    (void)sender;
    [self.services logMessage:[NSString stringWithFormat:@"Hopper MCP Bridge: %@", self.bridgeServer.socketPath]];
}
@end
