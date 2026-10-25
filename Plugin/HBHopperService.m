#import "HBHopperService+Internal.h"

@interface NSObject (HBHostDocumentAccess)
+ (id)sharedDocumentController;
- (NSArray *)documents;
- (NSString *)displayName;
+ (id)sharedApplication;
- (BOOL)isActive;
@end

@interface HBBridgeSession : NSObject
@property(nonatomic, strong) HBObjectStore *objects;
@property(nonatomic, strong) HBInvocation *invocation;
@property(nonatomic, weak) NSObject<HPDocument> *selectedDocument;
@property(nonatomic, strong) NSDate *lastUsed;
@end
@implementation HBBridgeSession
- (instancetype)init {
    self = [super init];
    if (self) {
        self.objects = [HBObjectStore new];
        self.invocation = [[HBInvocation alloc] initWithObjectStore:self.objects];
        self.lastUsed = [NSDate date];
    }
    return self;
}
@end

@implementation HBHopperService
- (instancetype)initWithServices:(NSObject<HPHopperServices> *)services {
    self = [super init];
    if (self) {
        self.services = services;
        self.sessions = [NSMutableDictionary dictionary];
    }
    return self;
}
- (HBObjectStore *)objectStore { return self.currentSession.objects; }
- (HBInvocation *)invocation { return self.currentSession.invocation; }
- (NSObject<HPDocument> *)selectedDocument { return self.currentSession.selectedDocument; }
- (void)setSelectedDocument:(NSObject<HPDocument> *)document { self.currentSession.selectedDocument = document; }
- (void)fail:(NSString *)message {
    @throw [NSException exceptionWithName:@"HopperError" reason:message userInfo:nil];
}
- (NSArray *)documents {
    Class documentControllerClass = NSClassFromString(@"NSDocumentController");
    return [[documentControllerClass sharedDocumentController] documents] ?: @[];
}
- (NSString *)nameForDocument:(id)document {
    return [document respondsToSelector:@selector(displayName)] ? [document displayName] : NSStringFromClass([document class]);
}
- (NSObject<HPDocument> *)documentForArguments:(NSDictionary *)arguments {
    NSArray *documents = [self documents];
    [self.objectStore removeObjectsForClosedDocuments:documents];
    id value = arguments[@"document"];
    if ([value isKindOfClass:NSDictionary.class] && value[@"$ref"]) {
        id document = [self.objectStore decodeObject:value];
        if ([documents indexOfObjectIdenticalTo:document] == NSNotFound) [self fail:@"The supplied object is not an open Hopper document"];
        return document;
    }
    if (value && value != NSNull.null) {
        NSMutableArray *matching = [NSMutableArray array];
        for (id document in documents) if ([[self nameForDocument:document] isEqualToString:value]) [matching addObject:document];
        if (matching.count > 1) [self fail:@"Several documents share this name; pass a document object reference"];
        if (!matching.count) [self fail:[NSString stringWithFormat:@"Document not found: %@", value]];
        return matching.firstObject;
    }
    if (self.selectedDocument && [documents indexOfObjectIdenticalTo:self.selectedDocument] != NSNotFound) return self.selectedDocument;
    id current = [self.services currentDocument];
    if (current && [documents indexOfObjectIdenticalTo:current] != NSNotFound) return current;
    if (documents.count == 1) return documents.firstObject;
    if (!documents.count) [self fail:@"Open a binary in Hopper first"];
    [self fail:@"Pass an explicit document name or object reference when Hopper has several open documents"];
    return nil;
}
- (NSString *)hexAddress:(uint64_t)address {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}
- (uint64_t)addressFromValue:(id)value file:(id<HPDisassembledFile>)file {
    if ([value isKindOfClass:NSNumber.class]) return [value unsignedLongLongValue];
    if ([value isKindOfClass:NSString.class]) {
        Address named = [file findVirtualAddressNamed:value];
        if (named != BAD_ADDRESS) return named;
        NSScanner *scanner = [NSScanner scannerWithString:value];
        unsigned long long address;
        if ([scanner scanHexLongLong:&address] && scanner.isAtEnd) return address;
    }
    [self fail:[NSString stringWithFormat:@"Invalid address or symbol: %@", value]];
    return BAD_ADDRESS;
}
- (NSObject<HPProcedure> *)procedureForArguments:(NSDictionary *)arguments file:(id<HPDisassembledFile>)file document:(id<HPDocument>)document {
    id value = arguments[@"procedure"] ?: arguments[@"address"];
    Address address = value ? [self addressFromValue:value file:file] : [document currentAddress];
    id procedure = [file procedureAt:address];
    if (!procedure) [self fail:[NSString stringWithFormat:@"No procedure contains %@", [self hexAddress:address]]];
    return procedure;
}
- (id)objectForArguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document {
    id target = arguments[@"target"] ?: arguments[@"kind"] ?: @"file";
    if ([target isKindOfClass:NSDictionary.class] && target[@"$ref"]) return [self.objectStore decodeObject:target];
    if (![target isKindOfClass:NSString.class]) [self fail:@"Target must be a root kind or an object reference"];
    if ([target isEqualToString:@"services"]) return self.services;
    if ([target isEqualToString:@"document"]) return document;
    id<HPDisassembledFile> file = [document disassembledFile];
    if (!file) [self fail:@"The document has no disassembled file"];
    if ([target isEqualToString:@"file"]) return file;
    if ([target isEqualToString:@"cpu_context"]) return [file buildCPUContext];
    if ([target isEqualToString:@"procedure"]) return [self procedureForArguments:arguments file:file document:document];
    if ([target isEqualToString:@"basic_block"]) {
        id<HPProcedure> procedure = [self procedureForArguments:arguments file:file document:document];
        NSUInteger index = [arguments[@"index"] unsignedIntegerValue];
        if (index >= [procedure basicBlockCount]) [self fail:@"Basic block index is out of bounds"];
        return [procedure basicBlockAtIndex:index];
    }
    if ([target isEqualToString:@"segment"]) {
        if (arguments[@"address"]) return [file segmentForVirtualAddress:[self addressFromValue:arguments[@"address"] file:file]];
        if (arguments[@"name"]) return [file segmentNamed:arguments[@"name"]];
        NSUInteger index = [arguments[@"index"] unsignedIntegerValue];
        NSArray *segments = [file segments];
        if (index >= segments.count) [self fail:@"Segment index is out of bounds"];
        return segments[index];
    }
    if ([target isEqualToString:@"section"]) {
        if (arguments[@"name"]) return [file sectionNamed:arguments[@"name"]];
        Address address = arguments[@"address"] ? [self addressFromValue:arguments[@"address"] file:file] : [document currentAddress];
        return [file sectionForVirtualAddress:address];
    }
    if ([target isEqualToString:@"type"]) return [file typeWithName:arguments[@"name"]];
    [self fail:[NSString stringWithFormat:@"Unknown root kind: %@", target]];
    return nil;
}
- (id)handleRequest:(NSDictionary *)request {
    NSString *method = request[@"method"];
    if (![method isEqualToString:@"status"] && ![method isEqualToString:@"call"]) [self fail:@"Unknown bridge method"];
    NSString *name = [method isEqualToString:@"status"] ? @"bridge_status" : request[@"name"];
    NSDictionary *arguments = request[@"arguments"] ?: @{};
    if (![name isKindOfClass:NSString.class] || ![arguments isKindOfClass:NSDictionary.class]) [self fail:@"Expected a tool name and arguments object"];
    NSString *client = request[@"client"] ?: @"diagnostic";
    if (![client isKindOfClass:NSString.class] || !client.length || client.length > 128) [self fail:@"Invalid bridge client identifier"];
    if ([name isEqualToString:@"release_session"]) {
        [self.sessions removeObjectForKey:client];
        self.currentSession = nil;
        return @{@"released": @YES};
    }
    for (NSString *identifier in [self.sessions.allKeys copy]) {
        if ([self.sessions[identifier].lastUsed timeIntervalSinceNow] < -86400) [self.sessions removeObjectForKey:identifier];
    }
    HBBridgeSession *session = self.sessions[client];
    if (!session) {
        if (self.sessions.count >= 64) [self fail:@"Too many bridge clients; close unused MCP sessions"];
        session = [HBBridgeSession new];
        self.sessions[client] = session;
    }
    session.lastUsed = [NSDate date];
    self.currentSession = session;
    if ([name isEqualToString:@"bridge_status"]) {
        return @{@"version": @"1.0.0", @"hopper_version": [self.services hopperVersionString] ?: @"unknown",
            @"pid": @([NSProcessInfo processInfo].processIdentifier), @"sdk_abi": @(HB_HOPPER_SDK_VERSION),
            @"bundle_path": NSBundle.mainBundle.bundlePath, @"document_count": @([self documents].count),
            @"application_active": @([[NSClassFromString(@"NSApplication") sharedApplication] isActive])};
    }
    if ([name isEqualToString:@"list_documents"]) {
        NSMutableArray *names = [NSMutableArray array];
        for (id document in [self documents]) [names addObject:[self nameForDocument:document]];
        return names;
    }
    if ([name isEqualToString:@"list_document_objects"]) {
        NSMutableArray *documents = [NSMutableArray array];
        for (id document in [self documents]) [documents addObject:@{@"name": [self nameForDocument:document], @"object": [self.objectStore encodeObject:document document:document]}];
        return documents;
    }
    if ([name isEqualToString:@"release_objects"]) {
        NSArray *references = arguments[@"references"];
        if (![references isKindOfClass:NSArray.class]) [self fail:@"references must be an array of reference strings"];
        [self.objectStore releaseReferences:references];
        return @{@"released": @(references.count)};
    }
    id target = arguments[@"target"] ?: arguments[@"kind"];
    BOOL servicesOnly = [target isKindOfClass:NSString.class] && [target isEqualToString:@"services"];
    NSObject<HPDocument> *document = servicesOnly ? nil : [self documentForArguments:arguments];
    if ([name isEqualToString:@"current_document"]) return [self nameForDocument:document];
    if ([name isEqualToString:@"set_current_document"]) {
        self.selectedDocument = document;
        return [self nameForDocument:document];
    }
    if ([name isEqualToString:@"get_object"]) {
        return [self.objectStore encodeObject:[self objectForArguments:arguments document:document] document:document];
    }
    if ([name isEqualToString:@"list_api"]) {
        NSArray *methods = [self.invocation methodsForObject:[self objectForArguments:arguments document:document] pattern:arguments[@"pattern"] includePrivate:[arguments[@"include_private"] boolValue]];
        NSUInteger offset = [arguments[@"offset"] unsignedIntegerValue];
        NSUInteger limit = arguments[@"limit"] ? [arguments[@"limit"] unsignedIntegerValue] : 100;
        if (!limit || limit > 1000) [self fail:@"API page size must be between 1 and 1000"];
        NSUInteger count = offset < methods.count ? MIN(limit, methods.count - offset) : 0;
        return @{@"total": @(methods.count), @"offset": @(offset), @"methods": count ? [methods subarrayWithRange:NSMakeRange(offset, count)] : @[]};
    }
    if ([name isEqualToString:@"invoke_api"]) {
        NSString *selector = arguments[@"selector"];
        NSArray *parameters = arguments[@"arguments"] ?: @[];
        if (![selector isKindOfClass:NSString.class] || ![parameters isKindOfClass:NSArray.class]) [self fail:@"Expected a selector string and arguments array"];
        return [self.invocation invokeTarget:[self objectForArguments:arguments document:document] selector:selector arguments:parameters document:document allowPrivate:[arguments[@"allow_private"] boolValue]];
    }
    id result = [self performReadTool:name arguments:arguments document:document];
    if (result) return result;
    result = [self performWriteTool:name arguments:arguments document:document];
    if (result) return result;
    [self fail:[NSString stringWithFormat:@"Unknown tool: %@", name]];
    return nil;
}
@end
