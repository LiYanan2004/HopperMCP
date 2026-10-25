#import "HBHopperService+Internal.h"

@interface NSObject (HBVerifiedQueries)
- (NSArray<NSNumber *> *)allStringAddresses;
- (NSString *)stringAtAddress:(Address)address;
- (Address)nextAddressOfVirtualAddress:(Address)address;
- (Address)previousAddressOfVirtualAddress:(Address)address;
- (NSUInteger)bookmarkCount;
- (Address)addressOfBookmarkAtIndex:(NSInteger)index;
- (NSString *)nameOfBookmarkAtIndex:(NSInteger)index;
- (id)signaturePseudoCode;
- (NSArray *)allLocalVariables;
- (NSString *)name;
- (int64_t)displacement;
@end

@implementation HBHopperService (Queries)
- (NSArray<NSObject<HPProcedure> *> *)proceduresInFile:(id<HPDisassembledFile>)file {
    NSMutableArray *procedures = [NSMutableArray array];
    for (id<HPSegment> segment in [file segments]) {
        for (NSUInteger index = 0; index < [segment procedureCount]; index++) {
            id procedure = [segment procedureAtIndex:index];
            if (procedure) [procedures addObject:procedure];
        }
    }
    return procedures;
}
- (NSRegularExpression *)expressionForArguments:(NSDictionary *)arguments {
    NSString *pattern = arguments[@"pattern"] ?: @".*";
    if (![pattern isKindOfClass:NSString.class] || pattern.length > 16384) [self fail:@"pattern must be a regular expression of at most 16384 characters"];
    NSError *error;
    NSRegularExpressionOptions options = [arguments[@"case_sensitive"] boolValue] ? 0 : NSRegularExpressionCaseInsensitive;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:&error];
    if (!expression) [self fail:error.localizedDescription];
    return expression;
}
- (NSDictionary *)procedureInformation:(NSObject<HPProcedure> *)procedure file:(id<HPDisassembledFile>)file detailed:(BOOL)detailed document:(NSObject<HPDocument> *)document {
    NSMutableArray *blocks = [NSMutableArray array];
    NSUInteger size = 0;
    for (NSUInteger index = 0; index < [procedure basicBlockCount]; index++) {
        id<HPBasicBlock> block = [procedure basicBlockAtIndex:index];
        Address start = [block from], end = [block to];
        id<HPSegment> segment = [file segmentForVirtualAddress:end];
        NSUInteger finalInstructionLength = MAX((NSUInteger)1, [segment getByteLengthAtVirtualAddress:end]);
        if (end >= start) size += (NSUInteger)(end - start) + finalInstructionLength;
        if (detailed) [blocks addObject:@{@"from": [self hexAddress:start], @"to": [self hexAddress:end]}];
    }
    NSMutableDictionary *result = [@{@"entrypoint": [self hexAddress:[procedure entryPoint]],
        @"name": [file nameForVirtualAddress:[procedure entryPoint]] ?: @"",
        @"basicblock_count": @([procedure basicBlockCount]), @"size": @(size), @"length": @(size)} mutableCopy];
    if (detailed) {
        result[@"basicblocks"] = blocks;
        id signature = [(id)procedure respondsToSelector:@selector(signaturePseudoCode)] ? [(id)procedure signaturePseudoCode] : nil;
        result[@"signature"] = [signature respondsToSelector:@selector(string)] ? [signature string] : @"";
        NSMutableArray *locals = [NSMutableArray array];
        if ([(id)procedure respondsToSelector:@selector(allLocalVariables)]) {
            for (id variable in [(id)procedure allLocalVariables]) {
                if ([variable respondsToSelector:@selector(name)] && [variable respondsToSelector:@selector(displacement)]) [locals addObject:@{@"name": [variable name] ?: @"", @"displacement": @([variable displacement])}];
                else [locals addObject:[self.objectStore encodeObject:variable document:document]];
            }
        }
        result[@"locals"] = locals;
    }
    return result;
}
- (NSString *)assemblyForProcedure:(id<HPProcedure>)procedure file:(id<HPDisassembledFile>)file {
    NSMutableString *result = [NSMutableString string];
    NSMutableArray<NSObject<HPBasicBlock> *> *blocks = [NSMutableArray array];
    for (NSUInteger index = 0; index < [procedure basicBlockCount]; index++) [blocks addObject:[procedure basicBlockAtIndex:index]];
    [blocks sortUsingComparator:^NSComparisonResult(id<HPBasicBlock> first, id<HPBasicBlock> second) {
        return [first from] < [second from] ? NSOrderedAscending : [first from] > [second from] ? NSOrderedDescending : NSOrderedSame;
    }];
    for (id<HPBasicBlock> block in blocks) {
        Address address = [block from], end = [block to];
        NSUInteger instructionCount = 0;
        while (address <= end && instructionCount++ < 1000000) {
            id<HPSegment> segment = [file segmentForVirtualAddress:address];
            if (!segment) break;
            NSArray *lines = [segment stringsForVirtualAddress:address includingDecorations:YES inlineComments:YES addressField:YES hexColumn:NO compactMode:NO];
            for (id<HPASMLine> line in lines) [result appendFormat:@"%@\n", [line string]];
            NSUInteger step = MAX((NSUInteger)1, [segment getByteLengthAtVirtualAddress:address]);
            if (UINT64_MAX - address < step) break;
            address += step;
            if (result.length > 16 * 1024 * 1024) [self fail:@"Assembly exceeds 16 MiB; use disassemble with a bounded instruction count"];
        }
    }
    return result;
}
- (id)performReadTool:(NSString *)name arguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document {
    id<HPDisassembledFile> file = [document disassembledFile];
    if (!file) [self fail:@"The document has no disassembled file"];
    Address address = arguments[@"address"] ? [self addressFromValue:arguments[@"address"] file:file] : [document currentAddress];
    if ([name isEqualToString:@"get_document_info"]) {
        return @{@"name": [self nameForDocument:document], @"path": [file originalFilePath] ?: @"",
            @"base_address": [self hexAddress:[file fileBaseAddress]], @"entry_point": [self hexAddress:[file firstEntryPoint]],
            @"segment_count": @([file segmentCount]), @"address_width": @([file addressSpaceWidthInBits]),
            @"analysis_active": @([document backgroundProcessActive]), @"waiting": @([document isWaiting])};
    }
    if ([name isEqualToString:@"current_address"]) return [self hexAddress:[document currentAddress]];
    if ([name isEqualToString:@"current_procedure"]) {
        id<HPProcedure> procedure = [file procedureAt:[document currentAddress]];
        return procedure ? [file nameForVirtualAddress:[procedure entryPoint]] ?: @"" : @"";
    }
    if ([name isEqualToString:@"list_segments"]) {
        NSMutableArray *segments = [NSMutableArray array];
        for (id<HPSegment> segment in [file segments]) {
            NSMutableArray *sections = [NSMutableArray array];
            for (id<HPSection> section in [segment sections]) [sections addObject:@{@"name": section.sectionName ?: @"", @"start": [self hexAddress:[section startAddress]], @"end": [self hexAddress:[section endAddress]]}];
            [segments addObject:@{@"name": segment.segmentName ?: @"", @"start": [self hexAddress:[segment startAddress]], @"end": [self hexAddress:[segment endAddress]], @"readable": @(segment.readable), @"writable": @(segment.writable), @"executable": @(segment.executable), @"sections": sections}];
        }
        return segments;
    }
    if ([@[@"list_procedures", @"search_procedures", @"list_procedure_size", @"list_procedure_info"] containsObject:name]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSRegularExpression *expression = [name isEqualToString:@"search_procedures"] ? [self expressionForArguments:arguments] : nil;
        for (NSObject<HPProcedure> *procedure in [self proceduresInFile:file]) {
            NSString *label = [file nameForVirtualAddress:[procedure entryPoint]] ?: @"";
            if (expression && ![expression firstMatchInString:label options:0 range:NSMakeRange(0, label.length)]) continue;
            BOOL detailed = [name isEqualToString:@"list_procedure_info"];
            result[[self hexAddress:[procedure entryPoint]]] = ([name isEqualToString:@"list_procedure_size"] || detailed) ? [self procedureInformation:procedure file:file detailed:detailed document:document] : label;
        }
        return result;
    }
    if ([@[@"procedure_info", @"procedure_address", @"procedure_assembly", @"procedure_pseudo_code", @"procedure_callers", @"procedure_callees"] containsObject:name]) {
        NSObject<HPProcedure> *procedure = [self procedureForArguments:arguments file:file document:document];
        if ([name isEqualToString:@"procedure_address"]) return [self hexAddress:[procedure entryPoint]];
        if ([name isEqualToString:@"procedure_info"]) return [self procedureInformation:procedure file:file detailed:YES document:document];
        if ([name isEqualToString:@"procedure_assembly"]) return [self assemblyForProcedure:procedure file:file];
        if ([name isEqualToString:@"procedure_pseudo_code"]) {
            if (![procedure respondsToSelector:@selector(completePseudoCode)]) [self fail:@"This Hopper version does not expose completePseudoCode"];
            id pseudoCode = [procedure completePseudoCode];
            if (!pseudoCode) [self fail:@"Hopper could not decompile this procedure"];
            return [pseudoCode string] ?: @"";
        }
        NSArray *related = [name isEqualToString:@"procedure_callers"] ? [procedure allCallerProcedures] : [procedure allCalleeProcedures];
        NSMutableArray *result = [NSMutableArray array];
        for (id<HPProcedure> target in related) [result addObject:[file nameForVirtualAddress:[target entryPoint]] ?: [self hexAddress:[target entryPoint]]];
        return result;
    }
    if ([@[@"list_names", @"search_name", @"list_strings", @"search_strings"] containsObject:name]) {
        BOOL strings = [name hasSuffix:@"strings"];
        BOOL search = [name hasPrefix:@"search"];
        NSRegularExpression *expression = search ? [self expressionForArguments:arguments] : nil;
        NSArray<NSNumber *> *addresses = strings ? [(id)file allStringAddresses] : [file allNamedAddresses];
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSNumber *number in addresses) {
            Address entry = number.unsignedLongLongValue;
            NSString *value = strings ? [(id)file stringAtAddress:entry] : [file nameForVirtualAddress:entry];
            if (!value) continue;
            if (expression && ![expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)]) continue;
            result[[self hexAddress:entry]] = value;
        }
        return result;
    }
    if ([name isEqualToString:@"address_name"]) return [file nameForVirtualAddress:address] ?: @"";
    if ([name isEqualToString:@"comment"]) return [file commentAtVirtualAddress:address] ?: @"";
    if ([name isEqualToString:@"inline_comment"]) return [file inlineCommentAtVirtualAddress:address] ?: @"";
    if ([name isEqualToString:@"next_address"]) return [self hexAddress:[(id)file nextAddressOfVirtualAddress:address]];
    if ([name isEqualToString:@"prev_address"]) return [self hexAddress:[(id)file previousAddressOfVirtualAddress:address]];
    if ([name isEqualToString:@"xrefs"]) {
        id<HPSegment> segment = [file segmentForVirtualAddress:address];
        NSMutableArray *result = [NSMutableArray array];
        for (NSNumber *reference in [segment referencesToAddress:address]) [result addObject:[self hexAddress:reference.unsignedLongLongValue]];
        return result;
    }
    if ([name isEqualToString:@"list_bookmarks"]) {
        NSMutableArray *result = [NSMutableArray array];
        for (NSUInteger index = 0; index < [(id)file bookmarkCount]; index++) {
            [result addObject:@{@"address": [self hexAddress:[(id)file addressOfBookmarkAtIndex:(NSInteger)index]], @"name": [(id)file nameOfBookmarkAtIndex:(NSInteger)index] ?: @""}];
        }
        return result;
    }
    if ([name isEqualToString:@"read_bytes"]) {
        NSUInteger length = [arguments[@"length"] unsignedIntegerValue];
        if (!length || length > 1024 * 1024 || UINT64_MAX - address < length) [self fail:@"Read length must be between 1 byte and 1 MiB without address overflow"];
        NSMutableData *data = [NSMutableData dataWithLength:length];
        uint8_t *bytes = data.mutableBytes;
        for (NSUInteger index = 0; index < length; index++) {
            if (![file hasMappedDataAt:address + index]) [self fail:@"The requested range contains unmapped bytes"];
            bytes[index] = [file readUInt8AtVirtualAddress:address + index];
        }
        NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
        for (NSUInteger index = 0; index < length; index++) [hex appendFormat:@"%02x", bytes[index]];
        return @{@"address": [self hexAddress:address], @"length": @(length), @"hex": hex, @"base64": [data base64EncodedStringWithOptions:0]};
    }
    if ([name isEqualToString:@"disassemble"]) {
        NSUInteger count = arguments[@"count"] ? [arguments[@"count"] unsignedIntegerValue] : 32;
        if (!count || count > 4096) [self fail:@"Instruction count must be between 1 and 4096"];
        NSMutableArray *result = [NSMutableArray array];
        for (NSUInteger index = 0; index < count; index++) {
            id<HPSegment> segment = [file segmentForVirtualAddress:address];
            if (!segment) break;
            NSMutableArray *lines = [NSMutableArray array];
            for (id<HPASMLine> line in [segment stringsForVirtualAddress:address includingDecorations:NO inlineComments:YES addressField:NO hexColumn:NO compactMode:NO]) [lines addObject:[line string]];
            NSUInteger length = MAX((NSUInteger)1, [segment getByteLengthAtVirtualAddress:address]);
            [result addObject:@{@"address": [self hexAddress:address], @"length": @(length), @"assembly": [lines componentsJoinedByString:@"\n"]}];
            if (UINT64_MAX - address < length) break;
            address += length;
        }
        return result;
    }
    if ([name isEqualToString:@"list_types"]) {
        NSArray *types = [file typeDatabase];
        NSUInteger offset = [arguments[@"offset"] unsignedIntegerValue];
        NSUInteger limit = arguments[@"limit"] ? [arguments[@"limit"] unsignedIntegerValue] : 100;
        if (!limit || limit > 1000) [self fail:@"Type page size must be between 1 and 1000"];
        NSUInteger count = offset < types.count ? MIN(limit, types.count - offset) : 0;
        return @{@"total": @(types.count), @"types": [self.objectStore encodeObject:count ? [types subarrayWithRange:NSMakeRange(offset, count)] : @[] document:document]};
    }
    return nil;
}
@end
