//
//  EnrollmentDiagnostics.m
//  GestaltEdit
//
//  Read-only enrollment state sources confirmed from iOS 27 IPSW symbols:
//  AssistantServices _AFIsLinwood* C functions and GenerativeModels
//  preferences. No join/enroll/force/set API is called.
//

#import "EnrollmentDiagnostics.h"

#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <string.h>

typedef BOOL (*LinwoodBoolFn)(void);

static NSString * const kAssistantServicesPath =
    @"/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices";

static void *gAssistantServicesLibrary = NULL;

static void EnrollmentLoadAssistantServices(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gAssistantServicesLibrary = dlopen(
            kAssistantServicesPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
    });
}

static LinwoodBoolFn EnrollmentLoadLinwoodFn(const char *name)
{
    if (!gAssistantServicesLibrary) return NULL;
    return (LinwoodBoolFn)dlsym(gAssistantServicesLibrary, name);
}

static id EnrollmentReadPreference(NSString *domain, NSString *key)
{
    CFTypeRef rawValue = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)domain);
    if (rawValue) {
        id value = (__bridge_transfer id)rawValue;
        return value ?: [NSNull null];
    }
    return [NSNull null];
}

static NSDictionary *EnrollmentEntry(
    NSString *domain, NSString *key, id value)
{
    BOOL present = value != nil && ![value isKindOfClass:NSNull.class];
    return @{
        @"domain": domain ?: @"",
        @"key": key ?: @"",
        @"present": @(present),
        @"value": present ? value : [NSNull null]
    };
}

NSDictionary *EnrollmentAssistantAvailability(void)
{
    EnrollmentLoadAssistantServices();

    NSArray<NSString *> *symbolNames = @[
        @"_AFIsLinwoodCapable",
        @"_AFIsLinwoodCapableIgnoringUserSetting",
        @"_AFIsLinwoodDevice",
        @"_AFIsLinwoodDismissalAvailable",
        @"_AFIsLinwoodEnabled",
        @"_AFIsLinwoodEnabledAndAvailable",
        @"_AFIsLinwoodEnabledAndWasEverAvailable",
        @"_AFIsLinwoodEnterpriseRestrictionAllowed",
        @"_AFIsLinwoodFFEnabled",
        @"_AFIsLinwoodUserSettingExplicitlySet",
        @"_AFIsLinwoodUserSettingOn"
    ];

    NSMutableArray *flags = [NSMutableArray array];
    for (NSString *name in symbolNames) {
        LinwoodBoolFn fn = EnrollmentLoadLinwoodFn(name.UTF8String);
        if (fn) {
            [flags addObject:@{
                @"name": name,
                @"available": @YES,
                @"value": @(fn())
            }];
        } else {
            [flags addObject:@{
                @"name": name,
                @"available": @NO,
                @"error": @"symbol not exported"
            }];
        }
    }

    NSString *loadError = @"";
    if (!gAssistantServicesLibrary) {
        const char *error = dlerror();
        loadError = error ? [NSString stringWithUTF8String:error]
                          : @"dlopen failed for AssistantServices";
    }

    return @{
        @"loaded": @(gAssistantServicesLibrary != NULL),
        @"libraryPath": kAssistantServicesPath,
        @"loadError": loadError,
        @"flags": flags
    };
}

NSDictionary *EnrollmentPreferencesSnapshot(void)
{
    NSMutableArray *entries = [NSMutableArray array];
    NSUserDefaults *standard = [NSUserDefaults standardUserDefaults];

    NSArray<NSString *> *standardKeys = @[
        @"com.apple.gms.enhancedSiri.availability",
        @"com.apple.gms.enhancedSiri.bootUUID",
        @"com.apple.gms.enhancedSiri.lastUpdated",
        @"com.apple.gms.enhancedSiri.reasons",
        @"com.apple.gms.enhancedSiri.unifiedReasons",
        @"com.apple.gms.enhancedSiri.wasEverAvailable",
        @"com.apple.gms.availability.forcedWaitlistStatus",
        @"com.apple.gms.availability.everInstalledApps",
        @"com.apple.gms.availability.pqaIndexingState",
        @"com.apple.gms.availability.secureInitializedUseCases"
    ];
    for (NSString *key in standardKeys) {
        id value = [standard objectForKey:key];
        [entries addObject:EnrollmentEntry(@"standard", key, value)];
    }

    NSDictionary<NSString *, NSArray<NSString *> *> *domains = @{
        @"com.apple.gms.enhancedSiri": @[
            @"availability",
            @"bootUUID",
            @"lastUpdated",
            @"reasons",
            @"unifiedReasons",
            @"wasEverAvailable"
        ],
        @"com.apple.gms.availability": @[
            @"forcedWaitlistStatus",
            @"everInstalledApps",
            @"pqaIndexingState",
            @"secureInitializedUseCases"
        ]
    };
    [domains enumerateKeysAndObjectsUsingBlock:
        ^(NSString *domain, NSArray<NSString *> *keys, BOOL *stop) {
            for (NSString *key in keys) {
                id value = EnrollmentReadPreference(domain, key);
                [entries addObject:EnrollmentEntry(domain, key, value)];
            }
        }];

    return @{ @"entries": entries };
}
