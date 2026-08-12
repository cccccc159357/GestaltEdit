//
//  EligibilityFileAccess.m
//  GestaltEdit
//
//  Read-only bad_query file access used by the Siri AI eligibility diagnostic.
//

#import "EligibilityFileAccess.h"
#import "BadQueryBridge.h"

#import <errno.h>
#import <fcntl.h>
#import <stdint.h>
#import <string.h>
#import <unistd.h>

static NSString * const kEligibilityFileErrorDomain =
    @"com.gestaltedit.eligibility.file";

static NSError *EligibilityFileError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:kEligibilityFileErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

NSData *EligibilityReadFile(NSString *path, NSError **error)
{
    if (!path.isAbsolutePath) {
        if (error) *error = EligibilityFileError(
            1, @"EligibilityReadFile requires an absolute path.");
        return nil;
    }
    if (!BadQueryBridgeAvailable()) {
        if (error) *error = EligibilityFileError(
            2, @"bad_query is unavailable (required ContainerManager or sandbox extension APIs are missing).");
        return nil;
    }

    NSString *badQueryDetail = nil;
    BadQueryLease *lease = [BadQueryLease leaseForPath:path
                                                 error:&badQueryDetail];
    if (!lease) {
        if (error) *error = EligibilityFileError(
            3, badQueryDetail ?: @"bad_query could not open the requested path.");
        return nil;
    }

    int fd = open(path.fileSystemRepresentation,
                  O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        if (error) *error = EligibilityFileError(
            4, [NSString stringWithFormat:
                @"Failed to open %@ read-only (errno=%d, %s).",
                path, errno, strerror(errno)]);
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[64 * 1024];
    ssize_t bytesRead = 0;
    while (1) {
        bytesRead = read(fd, buffer, sizeof(buffer));
        if (bytesRead > 0) {
            [data appendBytes:buffer length:(NSUInteger)bytesRead];
            continue;
        }
        if (bytesRead < 0 && errno == EINTR) continue;
        break;
    }
    int readErrno = errno;
    close(fd);

    if (bytesRead < 0) {
        if (error) *error = EligibilityFileError(
            5, [NSString stringWithFormat:
                @"Failed to read %@ (errno=%d, %s).",
                path, readErrno, strerror(readErrno)]);
        return nil;
    }

    if (error) *error = nil;
    return data;
}
