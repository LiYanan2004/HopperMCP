#import "HBHopperService.h"
#import "Hopper.h"
#import "HBObjectStore.h"
#import "HBInvocation.h"
@class HBBridgeSession;

@interface HBHopperService ()
@property(nonatomic, strong) NSObject<HPHopperServices> *services;
@property(nonatomic, readonly) HBObjectStore *objectStore;
@property(nonatomic, readonly) HBInvocation *invocation;
@property(nonatomic, weak) NSObject<HPDocument> *selectedDocument;
@property(nonatomic, strong) HBBridgeSession *currentSession;
@property(nonatomic, strong) NSMutableDictionary<NSString *, HBBridgeSession *> *sessions;
- (NSArray *)documents;
- (NSString *)nameForDocument:(id)document;
- (NSObject<HPDocument> *)documentForArguments:(NSDictionary *)arguments;
- (NSObject<HPProcedure> *)procedureForArguments:(NSDictionary *)arguments file:(id<HPDisassembledFile>)file document:(id<HPDocument>)document;
- (id)objectForArguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document;
- (uint64_t)addressFromValue:(id)value file:(id<HPDisassembledFile>)file;
- (NSString *)hexAddress:(uint64_t)address;
- (void)fail:(NSString *)message;
@end

@interface HBHopperService (Queries)
- (id)performReadTool:(NSString *)name arguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document;
@end

@interface HBHopperService (Mutations)
- (id)performWriteTool:(NSString *)name arguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document;
@end
