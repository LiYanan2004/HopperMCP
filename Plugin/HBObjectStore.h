#import <Foundation/Foundation.h>

@interface HBObjectStore : NSObject
- (id)encodeObject:(id)object document:(id)document;
- (id)decodeObject:(id)value;
- (id)objectForReference:(NSString *)reference;
- (void)releaseReferences:(NSArray<NSString *> *)references;
- (void)removeObjectsForClosedDocuments:(NSArray *)documents;
@end
