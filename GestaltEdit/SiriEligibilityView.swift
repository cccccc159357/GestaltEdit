import SwiftUI

struct SiriEligibilityView: View {
    @State private var snapshot: SiriEligibilitySnapshot?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    List {
                        apiCapabilitySection(snapshot)
                        siriModeSection(snapshot)
                        relatedDomainsSection(snapshot)
                        allAnswersSection(snapshot)
                        rawResponseSection(snapshot)
                    }
                } else if isLoading {
                    ProgressView("正在通过 libsystem_eligibility 查询…")
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

    private func apiCapabilitySection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("libsystem_eligibility API") {
            LabeledContent("状态") {
                Text(snapshot.capability.loaded ? "可用" : "不可用")
                    .fontWeight(.semibold)
                    .foregroundStyle(snapshot.capability.loaded ? .green : .red)
            }
            LabeledContent("库路径") {
                Text(snapshot.capability.libraryPath)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }

            if !snapshot.capability.missingSymbols.isEmpty {
                LabeledContent("缺失符号") {
                    Text(snapshot.capability.missingSymbols.joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }

            if let loadError = snapshot.capability.loadError, !loadError.isEmpty {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func siriModeSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("OS_ELIGIBILITY_DOMAIN_SIRI_MODE") {
            if let siriMode = snapshot.siriMode {
                EligibilityDomainRowView(domain: siriMode)
            } else if !snapshot.capability.loaded {
                Label("libsystem_eligibility API 不可用", systemImage: "xmark.octagon")
            } else if !snapshot.allAnswers.success {
                Label("get_all_domain_answers 失败", systemImage: "exclamationmark.triangle")
            } else {
                Label("未找到该 domain", systemImage: "questionmark.circle")
            }
        }
    }

    private func relatedDomainsSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("相关 Siri AI / Apple Intelligence Domain") {
            ForEach(snapshot.relatedDomains) { domain in
                EligibilityDomainRowView(domain: domain)
            }

            if !snapshot.missingRelatedDomains.isEmpty {
                Text("get_all 未返回：\(snapshot.missingRelatedDomains.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func allAnswersSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("全部 Domain Answers") {
            LabeledContent("调用结果") {
                Text(snapshot.allAnswers.success ? "成功" : "失败")
                    .foregroundStyle(snapshot.allAnswers.success ? .green : .red)
            }
            LabeledContent("errno") {
                Text("\(snapshot.allAnswers.errnoValue)")
                    .monospacedDigit()
            }

            if let error = snapshot.allAnswers.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if snapshot.allAnswers.success {
                Text("\(snapshot.allDomains.count) 个 domain")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(snapshot.allDomains) { domain in
                    EligibilityDomainRowView(domain: domain)
                }
            }
        }
    }

    private func rawResponseSection(_ snapshot: SiriEligibilitySnapshot) -> some View {
        Section("API 原始返回") {
            DisclosureGroup {
                Text(EligibilityPlistText.xml(snapshot.allAnswers.rawDictionary))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("显示 get_all_domain_answers 原始结果", systemImage: "doc.text.magnifyingglass")
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

            if let apiErrno = domain.apiErrno {
                LabeledContent("API errno") {
                    Text("\(apiErrno)")
                        .monospacedDigit()
                }
            }
            if let apiError = domain.apiError, !apiError.isEmpty {
                Text(apiError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

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

            if let context = domain.context, !context.isEmpty {
                DisclosureGroup {
                    Text(EligibilityPlistText.xml(context))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("context", systemImage: "square.stack.3d.up")
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
