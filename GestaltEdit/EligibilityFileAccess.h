//
//  EligibilityFileAccess.h
//  GestaltEdit
//
//  Read-only file access for the Siri AI eligibility diagnostic.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Acquires a bad_query sandbox extension for an absolute path and reads the
/// file with O_RDONLY. This function never opens files for writing.
FOUNDATION_EXPORT NSData * _Nullable EligibilityReadFile(
    NSString * _Nonnull path,
    NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
