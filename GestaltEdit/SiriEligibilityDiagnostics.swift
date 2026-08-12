import Foundation

enum SiriEligibilityDomainKey {
    static let siriMode = "OS_ELIGIBILITY_DOMAIN_SIRI_MODE"
    static let siriModeNeedsConsent = "OS_ELIGIBILITY_DOMAIN_SIRI_MODE_NEEDS_CONSENT"
    static let greymatter = "OS_ELIGIBILITY_DOMAIN_GREYMATTER"
    static let foundationModels = "OS_ELIGIBILITY_DOMAIN_FOUNDATION_MODELS"
    static let personalQA = "OS_ELIGIBILITY_DOMAIN_PERSONAL_QA"
    static let siriWithAppIntents = "OS_ELIGIBILITY_DOMAIN_SIRI_WITH_APP_INTENTS"
}

struct EligibilityFileResult: Identifiable {
    let path: String
    let data: Data?
    let error: String?

    var id: String { path }
    var accessible: Bool { data != nil }
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
    let rawDictionary: [String: Any]

    var id: String { key }
    var rawText: String { EligibilityPlistText.xml(rawDictionary) }
}

struct EligibilityFileSection: Identifiable {
    let file: EligibilityFileResult
    let domains: [EligibilityDomainResult]
    let rawText: String?
    let parseError: String?

    var id: String { file.id }
}

struct SiriEligibilitySnapshot {
    let sections: [EligibilityFileSection]
    let siriMode: EligibilityDomainResult?
    let relatedDomains: [EligibilityDomainResult]
    let missingRelatedDomains: [String]

    var primarySection: EligibilityFileSection? { sections.first }
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
    static let primaryPath = "/private/var/db/os_eligibility/eligibility.plist"
    static let additionalPaths = [
        "/private/var/db/eligibilityd/eligibility.plist",
        "/private/var/db/eligibilityd/eligibility_inputs.plist"
    ]
    static let relatedDomainKeys = [
        SiriEligibilityDomainKey.siriMode,
        SiriEligibilityDomainKey.siriModeNeedsConsent,
        SiriEligibilityDomainKey.greymatter,
        SiriEligibilityDomainKey.foundationModels,
        SiriEligibilityDomainKey.personalQA,
        SiriEligibilityDomainKey.siriWithAppIntents
    ]

    static func load() -> SiriEligibilitySnapshot {
        let sections = ([primaryPath] + additionalPaths).map { path in
            let file = readFile(at: path)
            let dictionary = file.data.flatMap(parsePlist)
            let parseError = file.data != nil && dictionary == nil
                ? "文件可读取，但无法解析为 plist。"
                : nil
            return EligibilityFileSection(
                file: file,
                domains: domains(in: dictionary),
                rawText: dictionary.map(EligibilityPlistText.xml),
                parseError: parseError
            )
        }

        let primaryDomains = sections.first?.domains ?? []
        let domainsByKey = Dictionary(
            primaryDomains.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let presentRelated = relatedDomainKeys.compactMap { domainsByKey[$0] }
        let presentKeys = Set(presentRelated.map(\.key))
        let missing = relatedDomainKeys.filter { !presentKeys.contains($0) }

        return SiriEligibilitySnapshot(
            sections: sections,
            siriMode: domainsByKey[SiriEligibilityDomainKey.siriMode],
            relatedDomains: presentRelated,
            missingRelatedDomains: missing
        )
    }

    private static func readFile(at path: String) -> EligibilityFileResult {
        var error: NSError?
        guard let data = EligibilityReadFile(path, &error) else {
            return EligibilityFileResult(
                path: path,
                data: nil,
                error: error?.localizedDescription ?? "未知错误"
            )
        }
        return EligibilityFileResult(path: path, data: data, error: nil)
    }

    private static func parsePlist(_ data: Data) -> [String: Any]? {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ), let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func domains(in dictionary: [String: Any]?) -> [EligibilityDomainResult] {
        guard let dictionary else { return [] }
        return dictionary.keys.sorted().compactMap { key in
            guard let value = dictionary[key] as? [String: Any] else { return nil }
            let status = value["status"] as? [String: Any] ?? [:]
            return EligibilityDomainResult(
                key: key,
                answer: integer(value["os_eligibility_answer_t"]),
                answerSource: integer(value["os_eligibility_answer_source_t"]),
                statusRows: status.keys.sorted().compactMap { statusKey in
                    guard let statusValue = integer(status[statusKey]) else { return nil }
                    return EligibilityStatusRow(key: statusKey, value: statusValue)
                },
                rawDictionary: value
            )
        }
    }

    private static func integer(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }
}
