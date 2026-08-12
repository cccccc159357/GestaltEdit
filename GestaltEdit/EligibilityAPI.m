//
//  EligibilityAPI.m
//  GestaltEdit
//
//  Read-only libsystem_eligibility queries. Only the getter functions are
//  resolved; no force/reset/set/test-mode symbols are used.
//

#import "EligibilityAPI.h"

#import <dlfcn.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>
#import <xpc/xpc.h>

typedef uint64_t EligibilityDomainType;
typedef uint64_t EligibilityAnswer;
typedef uint64_t EligibilityAnswerSource;

typedef EligibilityDomainType (*EligibilityDomainForNameFn)(const char *name);
typedef int (*EligibilityGetAllAnswersFn)(xpc_object_t *answers);
typedef int (*EligibilityGetDomainAnswerFn)(
    EligibilityDomainType domain,
    EligibilityAnswer *answer,
    EligibilityAnswerSource *answerSource,
    xpc_object_t *status,
    xpc_object_t *context);

static NSString * const kEligibilityLibraryPath =
    @"/usr/lib/system/libsystem_eligibility.dylib";

static void *gEligibilityLibrary = NULL;
static EligibilityDomainForNameFn gDomainForName = NULL;
static EligibilityGetAllAnswersFn gGetAllAnswers = NULL;
static EligibilityGetDomainAnswerFn gGetDomainAnswer = NULL;

static void EligibilityLoadAPI(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gEligibilityLibrary = dlopen(
            kEligibilityLibraryPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (!gEligibilityLibrary) return;

        gDomainForName = (EligibilityDomainForNameFn)dlsym(
            gEligibilityLibrary, "os_eligibility_domain_for_name");
        gGetAllAnswers = (EligibilityGetAllAnswersFn)dlsym(
            gEligibilityLibrary, "os_eligibility_get_all_domain_answers");
        gGetDomainAnswer = (EligibilityGetDomainAnswerFn)dlsym(
            gEligibilityLibrary, "os_eligibility_get_domain_answer");
    });
}

static id EligibilityXPCToFoundation(xpc_object_t object)
{
    if (object == NULL) return [NSNull null];

    xpc_type_t type = xpc_get_type(object);
    if (type == XPC_TYPE_STRING) {
        const char *value = xpc_string_get_string_ptr(object);
        return value ? [NSString stringWithUTF8String:value] : @"";
    }
    if (type == XPC_TYPE_INT64) return @(xpc_int64_get_value(object));
    if (type == XPC_TYPE_UINT64) return @(xpc_uint64_get_value(object));
    if (type == XPC_TYPE_BOOL) return @(xpc_bool_get_value(object));

    if (type == XPC_TYPE_DICTIONARY) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        xpc_dictionary_apply(object, ^bool(const char *key, xpc_object_t value) {
            result[[NSString stringWithUTF8String:key]] =
                EligibilityXPCToFoundation(value);
            return true;
        });
        return result;
    }

    if (type == XPC_TYPE_ARRAY) {
        NSMutableArray *result = [NSMutableArray array];
        xpc_array_apply(object, ^bool(size_t index, xpc_object_t value) {
            [result addObject:EligibilityXPCToFoundation(value)];
            return true;
        });
        return result;
    }

    if (type == XPC_TYPE_DATA) {
        return [NSData dataWithBytes:xpc_data_get_bytes_ptr(object)
                              length:xpc_data_get_length(object)];
    }
    if (type == XPC_TYPE_NULL) return [NSNull null];

    if (type == XPC_TYPE_ERROR) {
        char *description = xpc_copy_description(object);
        if (description) {
            NSString *result = [NSString stringWithUTF8String:description];
            free(description);
            return result;
        }
        return @"xpc error";
    }

    return [NSString stringWithFormat:@"<xpc:%s>", xpc_type_get_name(type)];
}

NSDictionary *EligibilityAPICapability(void)
{
    EligibilityLoadAPI();
    NSMutableArray *missing = [NSMutableArray array];
    if (!gDomainForName) [missing addObject:@"os_eligibility_domain_for_name"];
    if (!gGetAllAnswers) [missing addObject:@"os_eligibility_get_all_domain_answers"];
    if (!gGetDomainAnswer) [missing addObject:@"os_eligibility_get_domain_answer"];

    NSString *loadError = @"";
    if (!gEligibilityLibrary) {
        const char *error = dlerror();
        loadError = error ? [NSString stringWithUTF8String:error]
                          : @"dlopen failed for libsystem_eligibility";
    }

    return @{
        @"loaded": @(gEligibilityLibrary != NULL && missing.count == 0),
        @"libraryPath": kEligibilityLibraryPath,
        @"loadError": loadError,
        @"missingSymbols": missing
    };
}

NSDictionary *EligibilityQueryAllAnswers(void)
{
    NSDictionary *capability = EligibilityAPICapability();
    if (![capability[@"loaded"] boolValue]) {
        return @{
            @"success": @NO,
            @"errno": @(ENOTSUP),
            @"error": capability[@"loadError"] ?: @"libsystem_eligibility unavailable",
            @"raw": @{}
        };
    }

    xpc_object_t answers = NULL;
    int result = gGetAllAnswers(&answers);
    BOOL hasAnswers = answers != NULL;
    NSDictionary *raw = hasAnswers ? EligibilityXPCToFoundation(answers) : @{};
    if (hasAnswers) xpc_release(answers);

    return @{
        @"success": @(result == 0 && hasAnswers),
        @"errno": @(result),
        @"error": result ? [NSString stringWithUTF8String:strerror(result)] : @"",
        @"raw": raw
    };
}

NSDictionary *EligibilityQueryDomainAnswer(NSString *domainName)
{
    NSDictionary *capability = EligibilityAPICapability();
    if (![capability[@"loaded"] boolValue]) {
        return @{
            @"success": @NO,
            @"domain": domainName ?: @"",
            @"errno": @(ENOTSUP),
            @"error": capability[@"loadError"] ?: @"libsystem_eligibility unavailable",
            @"raw": @{}
        };
    }

    EligibilityDomainType domainType = gDomainForName(domainName.UTF8String);
    if (domainType == 0) {
        return @{
            @"success": @NO,
            @"domain": domainName ?: @"",
            @"errno": @(EINVAL),
            @"error": @"os_eligibility_domain_for_name returned EligibilityDomainTypeInvalid (0)",
            @"raw": @{}
        };
    }

    EligibilityAnswer answer = 0;
    EligibilityAnswerSource answerSource = 0;
    xpc_object_t status = NULL;
    xpc_object_t context = NULL;
    int result = gGetDomainAnswer(
        domainType, &answer, &answerSource, &status, &context);

    NSDictionary *statusDict = status ? EligibilityXPCToFoundation(status) : @{};
    NSDictionary *contextDict = context ? EligibilityXPCToFoundation(context) : @{};
    if (status) xpc_release(status);
    if (context) xpc_release(context);

    NSMutableDictionary *raw = [NSMutableDictionary dictionary];
    raw[@"domain"] = domainName ?: @"";
    raw[@"domainType"] = @(domainType);
    raw[@"answer"] = @(answer);
    raw[@"answer_source"] = @(answerSource);
    if (status) raw[@"status"] = statusDict;
    if (context) raw[@"context"] = contextDict;

    return @{
        @"success": @(result == 0),
        @"domain": domainName ?: @"",
        @"errno": @(result),
        @"error": result ? [NSString stringWithUTF8String:strerror(result)] : @"",
        @"answer": @(answer),
        @"answer_source": @(answerSource),
        @"status": statusDict,
        @"context": contextDict,
        @"raw": raw
    };
}
