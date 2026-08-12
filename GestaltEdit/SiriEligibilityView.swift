import SwiftUI

struct SiriEligibilityView: View {
    @State private var snapshot: SiriEligibilitySnapshot?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    List {
                        fileAccessSection(snapshot)
                        siriModeSection(snapshot)
                        relatedDomainsSection(snapshot)

                        ForEach(snapshot.sections) { section in
                            domainSection(section)
                            rawSection(section)
                        }
                    }
                } else if isLoading {
                    ProgressView("正在读取 eligibility…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "读取失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text("无法生成诊断结果")
                    )
                }
            }
            .navigationTitle("Siri AI Eligibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("重新读取")
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        isLoading = true
        snapshot = SiriEligibilityDiagnostics.load()
        isLoading = false
    }

    private func fileAccessSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("文件可访问性") {
            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(section.file.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Text(section.file.accessible ? "可读取" : "不可读取")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(section.file.accessible ? .green : .red)
                    }
                    if let parseError = section.parseError {
                        Text(parseError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let error = section.file.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        Text("\(section.domains.count) 个 domain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func siriModeSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("OS_ELIGIBILITY_DOMAIN_SIRI_MODE") {
            if let siriMode = snapshot.siriMode {
                EligibilityDomainRowView(domain: siriMode)
            } else if let parseError = snapshot.primarySection?.parseError {
                Label("主 eligibility 文件无法解析", systemImage: "xmark.octagon")
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let error = snapshot.primarySection?.file.error {
                Label("主 eligibility 文件不可读取", systemImage: "xmark.octagon")
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Label("未找到该 domain", systemImage: "questionmark.circle")
                Text("文件可读取，但 plist 中没有 OS_ELIGIBILITY_DOMAIN_SIRI_MODE。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relatedDomainsSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("相关 Siri AI / Apple Intelligence Domain") {
            if snapshot.relatedDomains.isEmpty {
                Label("未发现相关 domain", systemImage: "questionmark.circle")
            } else {
                ForEach(snapshot.relatedDomains) { domain in
                    EligibilityDomainRowView(domain: domain)
                }
            }

            if !snapshot.missingRelatedDomains.isEmpty {
                Text("未出现：\(snapshot.missingRelatedDomains.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func domainSection(_ section: EligibilityFileSection) -> some View {
        Section {
            if section.domains.isEmpty {
                Text(section.file.accessible ? "未解析到 domain" : "文件不可读取")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(section.domains) { domain in
                    EligibilityDomainRowView(domain: domain)
                }
            }
        } header: {
            Text(section.file.path)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func rawSection(_ section: EligibilityFileSection) -> some View {
        if let rawText = section.rawText {
            Section("原始文件内容") {
                DisclosureGroup {
                    Text(rawText)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("显示原始 plist", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
    }
}

private struct EligibilityDomainRowView: View {
    let domain: EligibilityDomainResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(domain.key)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)

            LabeledContent("answer") {
                Text(domain.answer.map { String($0) } ?? "未读取")
                    .monospacedDigit()
            }
            Text(EligibilityAnswerText.answerLabel(domain.answer))
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("answer_source") {
                Text(domain.answerSource.map { String($0) } ?? "未读取")
                    .monospacedDigit()
            }
            Text(EligibilityAnswerText.answerSourceLabel(domain.answerSource))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !domain.statusRows.isEmpty {
                LabeledContent("status") {
                    Text("\(domain.statusRows.count) 项")
                        .monospacedDigit()
                }
                ForEach(domain.statusRows) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Text(row.key)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Text(EligibilityAnswerText.statusLabel(row.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            DisclosureGroup {
                Text(domain.rawText)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("原始值", systemImage: "doc.text")
            }
        }
    }
}
