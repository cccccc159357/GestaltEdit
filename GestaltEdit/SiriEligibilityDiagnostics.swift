import Foundation

enum SiriEligibilityDomainKey {
    static let siriMode = "OS_ELIGIBILITY_DOMAIN_SIRI_MODE"
    static let siriModeNeedsConsent = "OS_ELIGIBILITY_DOMAIN_SIRI_MODE_NEEDS_CONSENT"
    static let greymatter = "OS_ELIGIBILITY_DOMAIN_GREYMATTER"
    static let foundationModels = "OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS"
    static let personalQA = "OS_ELIGIBILITY_DOMAIN_PERSONAL_QA"
    static let siriWithAppIntents = "OS_ELIGIBILITY_DOMAIN_SIRI_WITH_APP_INTENTS"
}

struct EligibilityAPISummary {
    let loaded: Bool
    let libraryPath: String
    let loadError: String?
    let missingSymbols: [String]
}

struct EligibilityAPIResponse {
    let success: Bool
    let errnoValue: Int
    let error: String?
    let rawDictionary: [String: Any]
}

struct EligibilityStatusRow: Identifiable {
    let key: String
    let value: Int64

    var id: String { key }
}

struct EligibilityDomainResult: Identifiable {
    let key: String
    let answer: Int64?
    let answerSource: Int64?
    let statusRows: [EligibilityStatusRow]
    let context: [String: Any]?
    let apiErrno: Int?
    let apiError: String?
    let rawDictionary: [String: Any]

    var id: String { key }
    var rawText: String { EligibilityPlistText.xml(rawDictionary) }
}

struct SiriEligibilitySnapshot {
    let capability: EligibilityAPISummary
    let allAnswers: EligibilityAPIResponse
    let allDomains: [EligibilityDomainResult]
    let siriMode: EligibilityDomainResult?
    let relatedDomains: [EligibilityDomainResult]
    let missingRelatedDomains: [String]
}

enum EligibilityPlistText {
    static func xml(_ value: Any) -> String {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        ), let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

enum EligibilityAnswerText {
    static func answerLabel(_ value: Int64?) -> String {
        guard let value else { return "未读取" }
        switch value {
        case 0: return "0 · 无效（Invalid）"
        case 1: return "1 · 尚未确定（Not Yet Available）"
        case 2: return "2 · 不符合资格（Not Eligible）"
        case 3: return "3 · 可能符合（Maybe）"
        case 4: return "4 · 符合资格 / 已启用（Eligible）"
        default: return "\(value) · 未知值"
        }
    }

    static func answerSourceLabel(_ value: Int64?) -> String {
        guard let value else { return "未读取" }
        switch value {
        case 0: return "0 · 无效（Invalid）"
        case 1: return "1 · 计算得出（Computed）"
        case 2: return "2 · 强制（Forced）"
        default: return "\(value) · 公开头文件未收录"
        }
    }

    static func statusLabel(_ value: Int64) -> String {
        switch value {
        case 0: return "0 · 无（None）"
        case 1: return "1 · 尚未设置（Not Set）"
        case 2: return "2 · 不符合（Not Eligible）"
        case 3: return "3 · 符合（Eligible）"
        case 4: return "4 · Library Max（EUEnabler 公开 plist 中已启用域也使用此值，iOS 27 含义以原始值为准）"
        case 5: return "5 · 未指定错误（Unspecified Error）"
        case 6: return "6 · Token 过期（Token Expired）"
        case 7: return "7 · 无账户（No Account）"
        default: return "\(value) · 未知值"
        }
    }
}

enum SiriEligibilityDiagnostics {
    static let relatedDomainKeys = [
        SiriEligibilityDomainKey.siriMode,
        SiriEligibilityDomainKey.siriModeNeedsConsent,
        SiriEligibilityDomainKey.greymatter,
        SiriEligibilityDomainKey.foundationModels,
        SiriEligibilityDomainKey.personalQA,
        SiriEligibilityDomainKey.siriWithAppIntents
    ]

    static func load() -> SiriEligibilitySnapshot {
        let capability = parseCapability(
            EligibilityAPICapability() as? [String: Any] ?? [:]
        )
        let allResponse = parseAllAnswers(
            EligibilityQueryAllAnswers() as? [String: Any] ?? [:]
        )
        let allDomains = allDomains(from: allResponse.rawDictionary)
        let relatedDomains = relatedDomainKeys.map(domainDetail)
        let siriMode = relatedDomains.first {
            $0.key == SiriEligibilityDomainKey.siriMode
        }
        let presentKeys = Set(allResponse.rawDictionary.keys)
        let missing = relatedDomainKeys.filter { !presentKeys.contains($0) }

        return SiriEligibilitySnapshot(
            capability: capability,
            allAnswers: allResponse,
            allDomains: allDomains,
            siriMode: siriMode,
            relatedDomains: relatedDomains,
            missingRelatedDomains: missing
        )
    }

    private static func parseCapability(_ dictionary: [String: Any]) -> EligibilityAPISummary {
        EligibilityAPISummary(
            loaded: (dictionary["loaded"] as? NSNumber)?.boolValue ?? false,
            libraryPath: dictionary["libraryPath"] as? String ?? "",
            loadError: dictionary["loadError"] as? String,
            missingSymbols: dictionary["missingSymbols"] as? [String] ?? []
        )
    }

    private static func parseAllAnswers(_ dictionary: [String: Any]) -> EligibilityAPIResponse {
        EligibilityAPIResponse(
            success: (dictionary["success"] as? NSNumber)?.boolValue ?? false,
            errnoValue: (dictionary["errno"] as? NSNumber)?.intValue ?? -1,
            error: dictionary["error"] as? String,
            rawDictionary: dictionary["raw"] as? [String: Any] ?? [:]
        )
    }

    private static func allDomains(from raw: [String: Any]) -> [EligibilityDomainResult] {
        raw.keys.sorted().map { key in
            let value = raw[key] ?? NSNull()
            if let dictionary = value as? [String: Any] {
                let status = dictionary["status"] as? [String: Any] ?? [:]
                return EligibilityDomainResult(
                    key: key,
                    answer: integer(dictionary["os_eligibility_answer_t"]),
                    answerSource: integer(dictionary["os_eligibility_answer_source_t"]),
                    statusRows: statusRows(status),
                    context: dictionary["context"] as? [String: Any],
                    apiErrno: nil,
                    apiError: nil,
                    rawDictionary: dictionary
                )
            }
            let answer = (value as? NSNumber)?.int64Value
            return EligibilityDomainResult(
                key: key,
                answer: answer,
                answerSource: nil,
                statusRows: [],
                context: nil,
                apiErrno: nil,
                apiError: nil,
                rawDictionary: [key: value]
            )
        }
    }

    private static func domainDetail(_ key: String) -> EligibilityDomainResult {
        let detail = EligibilityQueryDomainAnswer(key) as? [String: Any] ?? [:]
        let raw = detail["raw"] as? [String: Any] ?? detail
        let status = detail["status"] as? [String: Any] ?? [:]
        let errnoValue = (detail["errno"] as? NSNumber)?.intValue

        return EligibilityDomainResult(
            key: key,
            answer: integer(detail["answer"]),
            answerSource: integer(detail["answer_source"]),
            statusRows: statusRows(status),
            context: detail["context"] as? [String: Any],
            apiErrno: errnoValue,
            apiError: detail["error"] as? String,
            rawDictionary: raw
        )
    }

    private static func statusRows(_ status: [String: Any]) -> [EligibilityStatusRow] {
        status.keys.sorted().compactMap { key in
            guard let value = integer(status[key]) else { return nil }
            return EligibilityStatusRow(key: key, value: value)
        }
    }

    private static func integer(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }
}
