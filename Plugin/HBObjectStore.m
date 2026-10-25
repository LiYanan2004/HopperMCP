#import "HBObjectStore.h"
#import <objc/runtime.h>

@interface HBObjectEntry : NSObject
@property(nonatomic, strong) id object;
@property(nonatomic, weak) id document;
@property(nonatomic) BOOL documentBound;
@end
@implementation HBObjectEntry
@end

@interface HBObjectStore ()
@property(nonatomic, copy) NSString *sessionIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, HBObjectEntry *> *entries;
@property(nonatomic, strong) NSMapTable *references;
@property(nonatomic) NSUInteger nextIdentifier;
@end

@implementation HBObjectStore
- (instancetype)init {
    self = [super init];
    if (self) {
        self.sessionIdentifier = NSUUID.UUID.UUIDString;
        self.entries = [NSMutableDictionary dictionary];
        self.references = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
    }
    return self;
}
- (id)encodeObject:(id)object document:(id)document {
    if (!object || object == NSNull.null) return NSNull.null;
    if ([object isKindOfClass:NSString.class] || [object isKindOfClass:NSNumber.class]) return object;
    if ([object isKindOfClass:NSAttributedString.class]) return [object string];
    if ([object isKindOfClass:NSData.class]) return @{@"$data": [object base64EncodedStringWithOptions:0], @"length": @([object length])};
    if ([object isKindOfClass:NSURL.class]) return @{@"$url": [object absoluteString]};
    if ([object isKindOfClass:NSDate.class]) return @{@"$date": @([object timeIntervalSince1970])};
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class] || [object isKindOfClass:NSOrderedSet.class]) {
        NSMutableArray *values = [NSMutableArray array];
        for (id value in object) [values addObject:[self encodeObject:value document:document]];
        return values;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (id key in object) values[[key description]] = [self encodeObject:object[key] document:document];
        return values;
    }
    if ([object isKindOfClass:NSValue.class] && strcmp([object objCType], @encode(NSRange)) == 0) {
        NSRange range = [object rangeValue];
        return @{@"$range": @{@"location": @(range.location), @"length": @(range.length)}};
    }
    NSString *reference = [self.references objectForKey:object];
    if (!reference || !self.entries[reference]) {
        if (self.entries.count >= 8192) @throw [NSException exceptionWithName:@"ObjectLimit" reason:@"Release unused object references before creating more objects" userInfo:nil];
        reference = [NSString stringWithFormat:@"%@:%lu", self.sessionIdentifier, (unsigned long)++self.nextIdentifier];
        HBObjectEntry *entry = [HBObjectEntry new];
        entry.object = object;
        entry.document = document;
        entry.documentBound = document != nil;
        self.entries[reference] = entry;
        [self.references setObject:reference forKey:object];
    }
    NSMutableArray *protocols = [NSMutableArray array];
    for (Class currentClass = [object class]; currentClass && currentClass != NSObject.class; currentClass = class_getSuperclass(currentClass)) {
        unsigned int count = 0;
        Protocol *__unsafe_unretained *list = class_copyProtocolList(currentClass, &count);
        for (unsigned int index = 0; index < count; index++) {
            NSString *name = NSStringFromProtocol(list[index]);
            if (![protocols containsObject:name]) [protocols addObject:name];
        }
        free(list);
    }
    return @{@"$ref": reference, @"class": NSStringFromClass([object class]), @"protocols": protocols};
}
- (id)objectForReference:(NSString *)reference {
    HBObjectEntry *entry = self.entries[reference];
    if (!entry || (entry.documentBound && !entry.document)) {
        @throw [NSException exceptionWithName:@"StaleObject" reason:@"The object reference expired or its document closed; resolve the object again" userInfo:nil];
    }
    return entry.object;
}
- (id)decodeObject:(id)value {
    if (value == NSNull.null) return nil;
    if ([value isKindOfClass:NSDictionary.class]) {
        if (value[@"$ref"]) return [self objectForReference:value[@"$ref"]];
        if (value[@"$data"]) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:value[@"$data"] options:0];
            if (!data) @throw [NSException exceptionWithName:@"InvalidData" reason:@"Invalid base64 data" userInfo:nil];
            return data;
        }
        if (value[@"$url"]) {
            NSURL *url = [NSURL URLWithString:value[@"$url"]];
            if (!url) @throw [NSException exceptionWithName:@"InvalidURL" reason:@"Invalid URL" userInfo:nil];
            return url;
        }
        if (value[@"$file"]) return [NSURL fileURLWithPath:value[@"$file"]];
        if (value[@"$date"]) return [NSDate dateWithTimeIntervalSince1970:[value[@"$date"] doubleValue]];
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in value) result[key] = [self decodeObject:value[key]] ?: NSNull.null;
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id child in value) [result addObject:[self decodeObject:child] ?: NSNull.null];
        return result;
    }
    return value;
}
- (void)releaseReferences:(NSArray<NSString *> *)references {
    for (NSString *reference in references) {
        HBObjectEntry *entry = self.entries[reference];
        if (entry) [self.references removeObjectForKey:entry.object];
        [self.entries removeObjectForKey:reference];
    }
}
- (void)removeObjectsForClosedDocuments:(NSArray *)documents {
    NSMutableArray *removed = [NSMutableArray array];
    for (NSString *reference in self.entries) {
        HBObjectEntry *entry = self.entries[reference];
        if (entry.documentBound && (!entry.document || [documents indexOfObjectIdenticalTo:entry.document] == NSNotFound)) [removed addObject:reference];
    }
    [self releaseReferences:removed];
}
@end
