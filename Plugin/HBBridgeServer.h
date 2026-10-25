#import <Foundation/Foundation.h>
@protocol HPHopperServices;

@interface HBBridgeServer : NSObject
@property(nonatomic, readonly, copy) NSString *socketPath;
- (instancetype)initWithServices:(NSObject<HPHopperServices> *)services;
- (void)start;
@end
