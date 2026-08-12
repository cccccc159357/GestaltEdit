//
//  EligibilityAPI.h
//  GestaltEdit
//
//  Read-only libsystem_eligibility queries for the SiriDiag page.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns whether the read-only libsystem_eligibility symbols were resolved.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EligibilityAPICapability(void);

/// Calls os_eligibility_get_all_domain_answers and converts the XPC reply.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EligibilityQueryAllAnswers(void);

/// Resolves a domain name with os_eligibility_domain_for_name, then calls
/// os_eligibility_get_domain_answer. Never calls force/write APIs.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *EligibilityQueryDomainAnswer(
    NSString * _Nonnull domainName);

NS_ASSUME_NONNULL_END
