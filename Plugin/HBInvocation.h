#import <Foundation/Foundation.h>
@class HBObjectStore;

@interface HBInvocation : NSObject
- (instancetype)initWithObjectStore:(HBObjectStore *)objectStore;
- (id)invokeTarget:(id)target selector:(NSString *)selector arguments:(NSArray *)arguments document:(id)document allowPrivate:(BOOL)allowPrivate;
- (NSArray<NSDictionary *> *)methodsForObject:(id)object pattern:(NSString *)pattern includePrivate:(BOOL)includePrivate;
@end
