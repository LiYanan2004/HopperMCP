#import "HBBridgeServer.h"
#import "HPHopperServices.h"
#import "HBHopperService.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

@interface HBBridgeServer ()
@property(nonatomic, strong) NSObject<HPHopperServices> *services;
@property(nonatomic, readwrite, copy) NSString *socketPath;
@property(nonatomic, copy) NSString *runtimeDirectory;
@property(nonatomic, strong) HBHopperService *hopperService;
@end

@implementation HBBridgeServer
- (instancetype)initWithServices:(NSObject<HPHopperServices> *)services {
    self = [super init];
    if (self) {
        self.services = services;
        self.hopperService = [[HBHopperService alloc] initWithServices:services];
        self.runtimeDirectory = [NSString stringWithFormat:@"/tmp/hopper-mcp-%u", getuid()];
        self.socketPath = [self.runtimeDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.sock", getpid()]];
    }
    return self;
}
- (void)start {
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}
- (id)handleRequest:(NSDictionary *)request {
    return [self.hopperService handleRequest:request];
}
- (void)run {
    @autoreleasepool {
        const char *directory = self.runtimeDirectory.fileSystemRepresentation;
        if (mkdir(directory, 0700) != 0 && errno != EEXIST) return;
        struct stat information;
        if (lstat(directory, &information) != 0 || !S_ISDIR(information.st_mode) || information.st_uid != getuid() || (information.st_mode & 077) != 0) return;
        int listener = socket(AF_UNIX, SOCK_STREAM, 0);
        if (listener < 0) return;
        struct sockaddr_un address = {0};
        address.sun_family = AF_UNIX;
        const char *path = self.socketPath.fileSystemRepresentation;
        if (strlen(path) >= sizeof(address.sun_path)) { close(listener); return; }
        strlcpy(address.sun_path, path, sizeof(address.sun_path));
        unlink(path);
        if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || chmod(path, 0600) != 0 || listen(listener, 8) != 0) {
            close(listener); unlink(path); return;
        }
        NSDictionary *metadata = @{@"pid": @(getpid()), @"socket": self.socketPath,
            @"bundle_path": NSBundle.mainBundle.bundlePath, @"protocol_version": @1};
        NSData *metadataData = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:NULL];
        NSString *metadataPath = [self.runtimeDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", getpid()]];
        [metadataData writeToFile:metadataPath options:NSDataWritingAtomic error:NULL];
        chmod(metadataPath.fileSystemRepresentation, 0600);
        while (YES) {
            int client = accept(listener, NULL, NULL);
            if (client < 0) { if (errno == EINTR) continue; break; }
            @autoreleasepool {
                uid_t peerUser; gid_t peerGroup;
                if (getpeereid(client, &peerUser, &peerGroup) != 0 || peerUser != getuid()) { close(client); continue; }
                struct timeval timeout = {.tv_sec = 10, .tv_usec = 0};
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
                setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
                int noSignal = 1;
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
                NSMutableData *input = [NSMutableData data];
                unsigned char buffer[4096];
                BOOL complete = NO;
                while (input.length <= 32 * 1024 * 1024) {
                    ssize_t count = read(client, buffer, sizeof(buffer));
                    if (count <= 0) break;
                    [input appendBytes:buffer length:(NSUInteger)count];
                    if (memchr(buffer, '\n', (size_t)count)) { complete = YES; break; }
                }
                if (complete) {
                    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:input options:0 error:NULL];
                    __block NSDictionary *response;
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        @try {
                            if (![request isKindOfClass:NSDictionary.class]) @throw [NSException exceptionWithName:@"InvalidRequest" reason:@"Expected a JSON object" userInfo:nil];
                            response = @{@"result": [self handleRequest:request] ?: NSNull.null};
                        } @catch (NSException *exception) {
                            response = @{@"error": @{@"code": @"bridge_error", @"message": exception.reason ?: exception.name}};
                        }
                    });
                    NSError *encodingError;
                    NSMutableData *output = [[NSJSONSerialization dataWithJSONObject:response options:0 error:&encodingError] mutableCopy];
                    if (!output || output.length > 32 * 1024 * 1024) {
                        NSDictionary *failure = @{@"error": @{@"code": @"serialization_error", @"message": encodingError.localizedDescription ?: @"Response exceeds 32 MiB; narrow the query"}};
                        output = [[NSJSONSerialization dataWithJSONObject:failure options:0 error:NULL] mutableCopy];
                    }
                    [output appendBytes:"\n" length:1];
                    NSUInteger offset = 0;
                    while (offset < output.length) {
                        ssize_t count = write(client, (const char *)output.bytes + offset, output.length - offset);
                        if (count < 0 && errno == EINTR) continue;
                        if (count <= 0) break;
                        offset += (NSUInteger)count;
                    }
                }
                close(client);
            }
        }
        close(listener);
        unlink(path);
        unlink(metadataPath.fileSystemRepresentation);
    }
}
@end
