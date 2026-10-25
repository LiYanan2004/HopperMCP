#import "HBHopperService+Internal.h"

@interface NSObject (HBVerifiedMutations)
- (void)setBookmarkAtVirtualAddress:(Address)address;
- (void)unsetBookmarkAtVirtualAddress:(Address)address;
- (NSInteger)indexOfBookmarkAtAddress:(Address)address;
- (void)setNameOfBookmarkAtIndex:(NSInteger)index to:(NSString *)name;
- (BOOL)saveHPDocument;
- (BOOL)saveHPDocumentAt:(NSURL *)url;
- (NSURL *)fileURL;
@end

@implementation HBHopperService (Mutations)
- (id)performWriteTool:(NSString *)name arguments:(NSDictionary *)arguments document:(NSObject<HPDocument> *)document {
    id<HPDisassembledFile> file = [document disassembledFile];
    Address address = arguments[@"address"] ? [self addressFromValue:arguments[@"address"] file:file] : [document currentAddress];
    if ([name isEqualToString:@"goto_address"]) {
        if (![file segmentForVirtualAddress:address]) [self fail:@"The address is outside the document's segments"];
        [document moveCursorToVirtualAddress:address];
        return [self hexAddress:address];
    }
    if ([name isEqualToString:@"set_comment"] || [name isEqualToString:@"set_inline_comment"]) {
        NSString *comment = arguments[@"comment"];
        if (comment && ![comment isKindOfClass:NSString.class]) [self fail:@"comment must be a string"];
        if ([name isEqualToString:@"set_comment"]) [file setComment:comment atVirtualAddress:address reason:CCReason_Script];
        else [file setInlineComment:comment atVirtualAddress:address reason:CCReason_Script];
        [document updateUI];
        return @"Success";
    }
    if ([name isEqualToString:@"set_address_name"]) {
        NSString *label = arguments[@"name"];
        if (label && ![label isKindOfClass:NSString.class]) [self fail:@"name must be a string"];
        [file setName:label forVirtualAddress:address reason:NCReason_Script];
        [document updateUI];
        return @"Success";
    }
    if ([name isEqualToString:@"set_addresses_names"]) {
        NSDictionary *names = arguments[@"names"];
        if (![names isKindOfClass:NSDictionary.class]) [self fail:@"names must map address strings to names"];
        NSMutableArray *updates = [NSMutableArray array];
        for (NSString *key in names) {
            if (![names[key] isKindOfClass:NSString.class]) [self fail:@"Every name must be a string"];
            [updates addObject:@{@"address": @([self addressFromValue:key file:file]), @"name": names[key]}];
        }
        for (NSDictionary *update in updates) [file setName:update[@"name"] forVirtualAddress:[update[@"address"] unsignedLongLongValue] reason:NCReason_Script];
        [document updateUI];
        return @"Success";
    }
    if ([name isEqualToString:@"set_bookmark"]) {
        if (arguments[@"name"] && ![arguments[@"name"] isKindOfClass:NSString.class]) [self fail:@"name must be a string"];
        [(id)file setBookmarkAtVirtualAddress:address];
        if (arguments[@"name"]) {
            NSInteger index = [(id)file indexOfBookmarkAtAddress:address];
            if (index >= 0) [(id)file setNameOfBookmarkAtIndex:index to:arguments[@"name"]];
        }
        [document updateUI];
        return @"Success";
    }
    if ([name isEqualToString:@"unset_bookmark"]) {
        [(id)file unsetBookmarkAtVirtualAddress:address];
        [document updateUI];
        return @"Success";
    }
    if ([name isEqualToString:@"write_bytes"]) {
        NSString *hex = arguments[@"hex"];
        if (![hex isKindOfClass:NSString.class]) [self fail:@"hex must contain hexadecimal byte pairs"];
        NSString *cleaned = [[hex componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
        if ([cleaned rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) [self fail:@"hex contains a non-hexadecimal character"];
        NSUInteger length = cleaned.length / 2;
        if (!length || cleaned.length % 2 || length > 1024 * 1024 || UINT64_MAX - address < length) [self fail:@"Write 1 byte to 1 MiB using complete hexadecimal pairs without address overflow"];
        NSMutableData *replacement = [NSMutableData dataWithLength:length];
        NSMutableData *original = [NSMutableData dataWithLength:length];
        uint8_t *bytes = replacement.mutableBytes, *previous = original.mutableBytes;
        for (NSUInteger index = 0; index < length; index++) {
            NSString *pair = [cleaned substringWithRange:NSMakeRange(index * 2, 2)];
            NSScanner *scanner = [NSScanner scannerWithString:pair];
            unsigned int value;
            if (![scanner scanHexInt:&value] || !scanner.isAtEnd || ![file hasMappedDataAt:address + index]) [self fail:@"Invalid hexadecimal data or an unmapped write range"];
            bytes[index] = (uint8_t)value;
            previous[index] = [file readUInt8AtVirtualAddress:address + index];
        }
        NSUInteger written = 0;
        for (; written < length; written++) if (![document writeUInt8:bytes[written] atVirtualAddress:address + written]) break;
        if (written != length) {
            for (NSUInteger index = 0; index < written; index++) [document writeUInt8:previous[index] atVirtualAddress:address + index];
            [self fail:@"Hopper rejected the byte patch; previously written bytes were restored"];
        }
        [document updateUI];
        return @{@"address": [self hexAddress:address], @"written": @(written)};
    }
    if ([name isEqualToString:@"assemble"]) {
        NSString *instruction = arguments[@"instruction"];
        if (![instruction isKindOfClass:NSString.class]) [self fail:@"instruction must be a string"];
        BOOL rawData = NO;
        NSError *error;
        NSData *data = [file assembleInstruction:instruction atAddress:address withCPUMode:[file cpuModeAtVirtualAddress:address] usingSyntaxVariant:[file userRequestedSyntaxIndex] isRawData:&rawData error:&error];
        if (!data) [self fail:error.localizedDescription ?: @"Hopper could not assemble the instruction"];
        NSMutableString *hex = [NSMutableString string];
        const uint8_t *bytes = data.bytes;
        for (NSUInteger index = 0; index < data.length; index++) [hex appendFormat:@"%02x", bytes[index]];
        return @{@"hex": hex, @"base64": [data base64EncodedStringWithOptions:0], @"is_raw_data": @(rawData)};
    }
    if ([name isEqualToString:@"save_document"]) {
        NSString *path = arguments[@"path"];
        if (path && (![path isKindOfClass:NSString.class] || !path.isAbsolutePath)) [self fail:@"path must be absolute"];
        NSURL *destination = path ? [NSURL fileURLWithPath:path] : [(id)document fileURL];
        if (!destination) [self fail:@"Supply an explicit .hop path for an unsaved document"];
        BOOL saved = [(id)document saveHPDocumentAt:destination];
        if (!saved) [self fail:@"Hopper could not save the document; supply an explicit writable .hop path"];
        return @{@"saved": @YES};
    }
    return nil;
}
@end
