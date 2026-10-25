#import <Foundation/Foundation.h>
@protocol HPHopperServices;

@interface HBHopperService : NSObject
- (instancetype)initWithServices:(NSObject<HPHopperServices> *)services;
- (id)handleRequest:(NSDictionary *)request;
@end
