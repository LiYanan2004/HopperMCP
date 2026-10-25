#import "HopperTool.h"
#import "HPHopperServices.h"
#import "HPHopperUUID.h"
#import "HBBridgeServer.h"

#ifndef HB_HOPPER_SDK_VERSION
#define HB_HOPPER_SDK_VERSION 4
#endif

enum { HBHopperSDKVersion = HB_HOPPER_SDK_VERSION };

// Access AppKit through Objective-C selectors to preserve Hopper 5's plugin loading compatibility.
@interface NSObject (HBToolMenuAccess)
+ (nullable NSObject *)sharedApplication;
- (nullable NSObject *)mainMenu;
- (nullable NSObject *)itemWithTitle:(nonnull NSString *)title;
- (nullable NSObject *)submenu;
- (NSUInteger)numberOfItems;
- (void)setHidden:(BOOL)hidden;
@end
