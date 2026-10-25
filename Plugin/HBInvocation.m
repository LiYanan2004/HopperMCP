#import "HBInvocation.h"
#import "HBObjectStore.h"
#import <objc/runtime.h>
#include <math.h>

static const char *HBUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL HBForbiddenSelector(NSString *selector) {
    static NSSet *selectors;
    if (!selectors) selectors = [NSSet setWithArray:@[@"dealloc", @"release", @"retain", @"autorelease", @"retainCount", @"finalize", @"alloc", @"allocWithZone:", @"init", @"load", @"unload", @"setClass:", @"forwardInvocation:", @"performSelector:", @"performSelector:withObject:", @"performSelector:withObject:withObject:"]];
    NSString *lowercase = selector.lowercaseString;
    return [selectors containsObject:selector] || [selector hasPrefix:@"_"] || [selector hasPrefix:@"initWith"] ||
        [selector hasPrefix:@"performSelector"] || [selector hasPrefix:@"beginToWait"] || [selector isEqualToString:@"endWaiting"] ||
        [lowercase containsString:@"activate"] || [lowercase containsString:@"makekey"] || [lowercase containsString:@"orderfront"] ||
        [lowercase containsString:@"orderwindow"] || [lowercase containsString:@"bringtofront"] || [lowercase hasPrefix:@"showwindow"] ||
        [lowercase hasPrefix:@"displayalert"] || [lowercase hasPrefix:@"runmodal"];
}

@interface HBInvocation ()
@property(nonatomic, strong) HBObjectStore *objectStore;
@property(nonatomic, strong) NSSet<NSString *> *publicSelectors;
@end

@implementation HBInvocation
- (instancetype)initWithObjectStore:(HBObjectStore *)objectStore {
    self = [super init];
    if (self) {
        self.objectStore = objectStore;
        NSURL *url = [[NSBundle bundleForClass:HBInvocation.class] URLForResource:@"api-native" withExtension:@"json"];
        NSArray *catalog = url ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL] : nil;
        NSMutableSet *selectors = [NSMutableSet set];
        for (NSDictionary *entry in catalog) if (![entry[@"private"] boolValue]) [selectors addObject:entry[@"selector"]];
        self.publicSelectors = selectors;
    }
    return self;
}
- (void)raise:(NSString *)message {
    @throw [NSException exceptionWithName:@"InvalidArgument" reason:message userInfo:nil];
}
- (NSNumber *)numberFromValue:(id)value {
    if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) return value;
    if ([value isKindOfClass:NSString.class]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        if ([value hasPrefix:@"0x"] || [value hasPrefix:@"0X"]) {
            unsigned long long number;
            if ([scanner scanHexLongLong:&number] && scanner.isAtEnd) return @(number);
        } else {
            long long number;
            if ([scanner scanLongLong:&number] && scanner.isAtEnd) return @(number);
        }
    }
    [self raise:@"Expected a number or a hexadecimal address"];
    return nil;
}
- (void)writeValue:(id)value type:(const char *)rawType bytes:(void *)bytes retained:(NSMutableArray *)retained {
    const char *type = HBUnqualifiedType(rawType);
    if (*type == '@') {
        if (type[1] == '?') {
            if (value != NSNull.null) [self raise:@"Callback blocks accept null through invoke_api; use a dedicated callback-aware tool for executable callbacks"];
            id block = nil;
            memcpy(bytes, (const void *)&block, sizeof(block));
        } else {
            id object = [self.objectStore decodeObject:value];
            if (object) [retained addObject:object];
            memcpy(bytes, (const void *)&object, sizeof(object));
        }
        return;
    }
    if (*type == ':') {
        if (![value isKindOfClass:NSString.class]) [self raise:@"Expected a selector string"];
        SEL selector = NSSelectorFromString(value);
        memcpy(bytes, &selector, sizeof(selector));
        return;
    }
    if (*type == '*') {
        if (![value isKindOfClass:NSString.class]) [self raise:@"Expected a C string"];
        NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *terminated = [data mutableCopy];
        [terminated appendBytes:"\0" length:1];
        [retained addObject:terminated];
        const char *pointer = terminated.bytes;
        memcpy(bytes, &pointer, sizeof(pointer));
        return;
    }
    if (*type == '{') {
        NSDictionary *fields = [value isKindOfClass:NSDictionary.class] ? value : nil;
        if (strcmp(type, @encode(NSRange)) == 0) {
            fields = fields[@"$range"] ?: fields;
            NSRange range = NSMakeRange([[self numberFromValue:fields[@"location"]] unsignedIntegerValue], [[self numberFromValue:fields[@"length"]] unsignedIntegerValue]);
            memcpy(bytes, &range, sizeof(range));
            return;
        }
        NSString *encodedType = [NSString stringWithUTF8String:type];
        if ([encodedType hasSuffix:@"=QQ}"]) {
            fields = fields[@"$address_range"] ?: fields;
            uint64_t range[2] = {[[self numberFromValue:fields[@"from"]] unsignedLongLongValue], [[self numberFromValue:fields[@"length"] ?: fields[@"len"]] unsignedLongLongValue]};
            memcpy(bytes, range, sizeof(range));
            return;
        }
        if (fields[@"$bytes"]) {
            NSData *data = [[NSData alloc] initWithBase64EncodedString:fields[@"$bytes"] options:0];
            NSUInteger length;
            NSGetSizeAndAlignment(type, &length, NULL);
            if (!data || data.length != length) [self raise:@"Struct data must match its runtime size exactly"];
            memcpy(bytes, data.bytes, length);
            return;
        }
        [self raise:[NSString stringWithFormat:@"Use base64 $bytes for struct %s", type]];
    }
    NSNumber *number = [self numberFromValue:value];
#define HB_WRITE_SCALAR(code, scalarType, accessor) case code: { scalarType scalar = [number accessor]; if ([number compare:@(scalar)] != NSOrderedSame) [self raise:@"Integer argument is outside the runtime type's range or has a fractional value"]; memcpy(bytes, &scalar, sizeof(scalar)); return; }
    switch (*type) {
        HB_WRITE_SCALAR('B', BOOL, boolValue)
        HB_WRITE_SCALAR('c', signed char, charValue)
        HB_WRITE_SCALAR('C', unsigned char, unsignedCharValue)
        HB_WRITE_SCALAR('s', short, shortValue)
        HB_WRITE_SCALAR('S', unsigned short, unsignedShortValue)
        HB_WRITE_SCALAR('i', int, intValue)
        HB_WRITE_SCALAR('I', unsigned int, unsignedIntValue)
        HB_WRITE_SCALAR('l', long, longValue)
        HB_WRITE_SCALAR('L', unsigned long, unsignedLongValue)
        HB_WRITE_SCALAR('q', long long, longLongValue)
        HB_WRITE_SCALAR('Q', unsigned long long, unsignedLongLongValue)
        case 'f': { float scalar = number.floatValue; if (!isfinite(scalar)) [self raise:@"Floating-point argument is outside the float range"]; memcpy(bytes, &scalar, sizeof(scalar)); return; }
        case 'd': { double scalar = number.doubleValue; memcpy(bytes, &scalar, sizeof(scalar)); return; }
        default: [self raise:[NSString stringWithFormat:@"Unsupported argument encoding: %s", type]];
    }
#undef HB_WRITE_SCALAR
}
- (id)readValue:(const void *)bytes type:(const char *)rawType document:(id)document {
    const char *type = HBUnqualifiedType(rawType);
    if (*type == 'v') return NSNull.null;
    if (*type == '@') {
        __unsafe_unretained id object;
        memcpy(&object, bytes, sizeof(object));
        return [self.objectStore encodeObject:object document:document];
    }
    if (*type == '*') {
        const char *string;
        memcpy(&string, bytes, sizeof(string));
        return string ? [NSString stringWithUTF8String:string] ?: NSNull.null : NSNull.null;
    }
    if (*type == ':') {
        SEL selector;
        memcpy(&selector, bytes, sizeof(selector));
        return selector ? NSStringFromSelector(selector) : NSNull.null;
    }
    if (*type == '{') {
        if (strcmp(type, @encode(NSRange)) == 0) {
            NSRange range;
            memcpy(&range, bytes, sizeof(range));
            return @{@"location": @(range.location), @"length": @(range.length)};
        }
        NSString *encodedType = [NSString stringWithUTF8String:type];
        if ([encodedType hasSuffix:@"=QQ}"]) {
            const uint64_t *range = bytes;
            return @{@"from": @(range[0]), @"length": @(range[1])};
        }
        NSUInteger size;
        NSGetSizeAndAlignment(type, &size, NULL);
        return @{@"$type": encodedType, @"$bytes": [[NSData dataWithBytes:bytes length:size] base64EncodedStringWithOptions:0], @"size": @(size)};
    }
#define HB_READ_SCALAR(code, scalarType) case code: { scalarType scalar; memcpy(&scalar, bytes, sizeof(scalar)); return @(scalar); }
    switch (*type) {
        HB_READ_SCALAR('B', BOOL)
        HB_READ_SCALAR('c', signed char)
        HB_READ_SCALAR('C', unsigned char)
        HB_READ_SCALAR('s', short)
        HB_READ_SCALAR('S', unsigned short)
        HB_READ_SCALAR('i', int)
        HB_READ_SCALAR('I', unsigned int)
        HB_READ_SCALAR('l', long)
        HB_READ_SCALAR('L', unsigned long)
        case 'q': { int64_t scalar; memcpy(&scalar, bytes, sizeof(scalar)); return scalar < -9007199254740991LL || scalar > 9007199254740991LL ? [NSString stringWithFormat:@"%lld", (long long)scalar] : @(scalar); }
        case 'Q': { uint64_t scalar; memcpy(&scalar, bytes, sizeof(scalar)); return scalar > 9007199254740991ULL ? [NSString stringWithFormat:@"0x%llx", (unsigned long long)scalar] : @(scalar); }
        HB_READ_SCALAR('f', float)
        HB_READ_SCALAR('d', double)
        default: [self raise:[NSString stringWithFormat:@"Unsupported return encoding: %s", type]];
    }
#undef HB_READ_SCALAR
    return NSNull.null;
}
- (id)invokeTarget:(id)target selector:(NSString *)selectorName arguments:(NSArray *)arguments document:(id)document allowPrivate:(BOOL)allowPrivate {
    if (!target) [self raise:@"The target object is unavailable"];
    if (HBForbiddenSelector(selectorName)) [self raise:@"This selector controls window activation, modal interaction, persistent waiting, or Objective-C lifecycle and is unavailable through MCP"];
    if (!allowPrivate && ![self.publicSelectors containsObject:selectorName]) [self raise:@"This selector is outside the SDK catalog. Inspect its implementation and pass allow_private:true to invoke a private method"];
    if ([selectorName isEqualToString:@"saveHPDocumentAt:"] && (arguments.count != 1 || ![[self.objectStore decodeObject:arguments.firstObject] isKindOfClass:NSURL.class])) [self raise:@"saveHPDocumentAt: requires an NSURL argument; use save_document or {$file:absolutePath}"];
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) [self raise:[NSString stringWithFormat:@"%@ does not implement %@ in this Hopper version", NSStringFromClass([target class]), selectorName]];
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature.numberOfArguments != arguments.count + 2) [self raise:@"Argument count does not match the runtime method signature"];
    const char *returnType = HBUnqualifiedType(signature.methodReturnType);
    if (strchr("^([#?", *returnType)) [self raise:@"Pointer, union, array and class return values require a dedicated adapter"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    NSMutableArray *retained = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *outputs = [NSMutableArray array];
    for (NSUInteger index = 0; index < arguments.count; index++) {
        const char *type = HBUnqualifiedType([signature getArgumentTypeAtIndex:index + 2]);
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        NSMutableData *storage = [NSMutableData dataWithLength:MAX(size, sizeof(void *))];
        [retained addObject:storage];
        id value = arguments[index];
        if (*type == '^') {
            if (value == NSNull.null) {
                void *pointer = NULL;
                [invocation setArgument:&pointer atIndex:index + 2];
                continue;
            }
            if (![value isKindOfClass:NSDictionary.class]) [self raise:@"Pointer arguments require null, {$out:true}, or {$buffer:base64,size:number}"];
            const char *pointee = HBUnqualifiedType(type + 1);
            NSMutableData *buffer = nil;
            if (value[@"$buffer"] || value[@"size"]) {
                NSUInteger length = [value[@"size"] unsignedIntegerValue];
                NSData *initial = value[@"$buffer"] ? [[NSData alloc] initWithBase64EncodedString:value[@"$buffer"] options:0] : nil;
                if (value[@"$buffer"] && !initial) [self raise:@"Invalid buffer base64"];
                length = MAX(length, initial.length);
                if (!length || length > 16 * 1024 * 1024) [self raise:@"Buffer length must be between 1 byte and 16 MiB"];
                buffer = [NSMutableData dataWithLength:length];
                if (initial.length) memcpy(buffer.mutableBytes, initial.bytes, initial.length);
            } else if ([value[@"$out"] boolValue]) {
                if (*pointee == 'v' || *pointee == '^' || *pointee == '?') [self raise:@"Specify a size for untyped or nested pointer output"];
                NSUInteger length;
                NSGetSizeAndAlignment(pointee, &length, NULL);
                buffer = [NSMutableData dataWithLength:MAX(length, sizeof(void *))];
                if (value[@"value"]) [self writeValue:value[@"value"] type:pointee bytes:buffer.mutableBytes retained:retained];
            } else [self raise:@"Invalid pointer argument"];
            [retained addObject:buffer];
            void *pointer = buffer.mutableBytes;
            [invocation setArgument:&pointer atIndex:index + 2];
            [outputs addObject:@{@"index": @(index), @"buffer": buffer, @"type": [NSString stringWithUTF8String:pointee], @"raw": @(value[@"$buffer"] != nil || value[@"size"] != nil)}];
        } else {
            [self writeValue:value type:type bytes:storage.mutableBytes retained:retained];
            [invocation setArgument:storage.mutableBytes atIndex:index + 2];
        }
    }
    [invocation retainArguments];
    [invocation invoke];
    NSMutableData *returnStorage = [NSMutableData dataWithLength:MAX(signature.methodReturnLength, sizeof(void *))];
    if (signature.methodReturnLength) [invocation getReturnValue:returnStorage.mutableBytes];
    id result = [self readValue:returnStorage.bytes type:returnType document:document];
    if (!outputs.count) return result;
    NSMutableArray *encodedOutputs = [NSMutableArray array];
    for (NSDictionary *output in outputs) {
        NSData *buffer = output[@"buffer"];
        id value = [output[@"raw"] boolValue] ? @{@"$data": [buffer base64EncodedStringWithOptions:0], @"length": @(buffer.length)} : [self readValue:buffer.bytes type:[output[@"type"] UTF8String] document:document];
        [encodedOutputs addObject:@{@"index": output[@"index"], @"value": value}];
    }
    return @{@"return": result, @"outputs": encodedOutputs};
}
- (NSArray<NSDictionary *> *)methodsForObject:(id)object pattern:(NSString *)pattern includePrivate:(BOOL)includePrivate {
    NSMutableDictionary *methods = [NSMutableDictionary dictionary];
    NSRegularExpression *expression = pattern.length ? [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL] : nil;
    if (pattern.length && !expression) [self raise:@"Invalid method search regular expression"];
    for (Class currentClass = [object class]; currentClass && currentClass != NSObject.class; currentClass = class_getSuperclass(currentClass)) {
        if ([[NSBundle bundleForClass:currentClass].bundlePath hasPrefix:@"/System/Library/"]) break;
        unsigned int count = 0;
        Method *list = class_copyMethodList(currentClass, &count);
        for (unsigned int index = 0; index < count; index++) {
            SEL selector = method_getName(list[index]);
            NSString *name = NSStringFromSelector(selector);
            if (HBForbiddenSelector(name) || methods[name]) continue;
            BOOL public = [self.publicSelectors containsObject:name];
            if (!public && !includePrivate) continue;
            if (expression && ![expression firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) continue;
            NSMethodSignature *signature = [object methodSignatureForSelector:selector];
            NSMutableArray *arguments = [NSMutableArray array];
            for (NSUInteger argumentIndex = 2; argumentIndex < signature.numberOfArguments; argumentIndex++) [arguments addObject:[NSString stringWithUTF8String:[signature getArgumentTypeAtIndex:argumentIndex]]];
            const char *returnType = HBUnqualifiedType(signature.methodReturnType);
            BOOL callable = strchr("^([#?", *returnType) == NULL;
            methods[name] = @{@"selector": name, @"declaring_class": NSStringFromClass(currentClass), @"return_type": [NSString stringWithUTF8String:signature.methodReturnType], @"argument_types": arguments, @"scope": public ? @"sdk" : @"private", @"callable": @(callable)};
        }
        free(list);
    }
    NSArray *names = [[methods allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in names) [result addObject:methods[name]];
    return result;
}
@end
