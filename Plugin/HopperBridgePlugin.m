#import <Foundation/Foundation.h>
#import "HopperTool.h"
#import "HPHopperServices.h"
#import "HBBridgeServer.h"

@interface HopperBridgePlugin : NSObject <HopperTool>
@property(nonatomic, strong) NSObject<HPHopperServices> *services;
@property(nonatomic, strong) HBBridgeServer *bridgeServer;
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
    }
    return self;
}
- (NSArray<NSDictionary<NSString *, id> *> *)toolMenuDescription {
    return @[@{HPM_TITLE: @"MCP Bridge Status", HPM_SELECTOR: @"showBridgeStatus:"}];
}
- (void)showBridgeStatus:(id)sender {
    (void)sender;
    [self.services logMessage:[NSString stringWithFormat:@"Hopper MCP Bridge: %@", self.bridgeServer.socketPath]];
}
@end
