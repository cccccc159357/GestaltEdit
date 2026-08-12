//
//  EnrollmentDiagnostics.h
//  GestaltEdit
//
//  Read-only Siri AI enrollment diagnostics from AssistantServices and
//  GenerativeModels preferences.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Calls the read-only _AFIsLinwood* C functions exported by AssistantServices.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EnrollmentAssistantAvailability(void);

/// Reads the GenerativeModels enrollment preference keys confirmed in the
/// iOS 27 IPSW diffs. This only reads values; it never writes preferences.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EnrollmentPreferencesSnapshot(void);

NS_ASSUME_NONNULL_END
