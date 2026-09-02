import SwiftUI

/// 거래내역서를 장부에 넣기 전에 **사람이 확인하는 화면.**
///
/// 예전에는 불러오기를 누르면 곧바로 저장했다. 그때는 앱이 통장을 베끼는 게 전부라
/// 확인할 것이 없었는데, 이제는 **청구서와 맞춰 적요·분할까지 만들어 낸다.**
/// 기계가 지어낸 이름이 장부에 그대로 들어가면 안 되므로 한 번 보여준다.
///
/// ```
/// 확인이 필요해요        ← 후보가 여럿이라 사람이 골라야 하는 것
/// 청구서와 맞았어요       ← 자동으로 정해진 것
/// 청구 없이 넣어요        ← 맞는 청구가 없는 것 (ATM 출금·이자·회비 입금)
/// 이미 장부에 있어요      ← 같은 내역서를 두 번 불러왔을 때
/// ```
///
/// **일이 남은 것이 맨 위다.** 내역서 순서대로 세우면 손댈 줄을 찾으려고 22줄을
/// 훑어야 한다.
struct StatementImportView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let statement: StatementFile
    /// 이 내역서가 어느 통장 것인가. 토스에서 뽑으므로 모임통장이다.
    let account: Account

    @Environment(\.dismiss) private var dismiss

    @State private var matches: [StatementMatch] = []
    @State private var isPreparing = true
    @State private var isImporting = false
    @State private var picking: StatementMatch?

    private var needsChoice: [StatementMatch] {
        matches.filter { !$0.alreadyImported && $0.chosenId == nil && !$0.candidates.isEmpty }
    }
    private var matched: [StatementMatch] {
        matches.filter { !$0.alreadyImported && $0.chosenId != nil }
    }
    private var unmatched: [StatementMatch] {
        matches.filter { !$0.alreadyImported && $0.chosenId == nil && $0.candidates.isEmpty }
    }
    private var skipped: [StatementMatch] {
        matches.filter { $0.alreadyImported }
    }
    private var importCount: Int { matches.filter { !$0.alreadyImported }.count }

    var body: some View {
        NavigationView {
            Group {
                if isPreparing {
                    ProgressView("맞춰 보는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if matches.isEmpty {
                    EmptyStateView(title: "읽어낸 거래가 없어요", icon: "doc.richtext")
                } else {
                    list
                }
            }
            .navigationTitle("거래내역서 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("넣기\(importCount > 0 ? " (\(importCount))" : "")") { runImport() }
                            .fontWeight(.semibold)
                            .disabled(importCount == 0)
                    }
                }
            }
            .interactiveDismissDisabled(isImporting)
            .sheet(item: $picking) { match in
                CandidatePickerView(match: match) { chosenId in
                    if let idx = matches.firstIndex(where: { $0.id == match.id }) {
                        matches[idx].chosenId = chosenId
                    }
                }
            }
            .task {
                matches = await viewModel.prepareStatementImport(from: statement)
                isPreparing = false
            }
        }
    }

    private var list: some View {
        List {
            section("확인이 필요해요", needsChoice,
                    footer: "금액이 같은 청구 묶음이 여럿이라 어느 것인지 정해야 해요.")
            section("청구서와 맞았어요", matched,
                    footer: "금액이 정확히 맞고 다른 줄과 겹치지 않아 미리 골라 뒀어요. 눌러서 바꿀 수 있어요.")
            section("청구 없이 넣어요", unmatched,
                    footer: "맞는 청구가 없어요. 적요와 분류는 넣은 뒤에 손으로 적으면 돼요.")
            section("이미 장부에 있어요", skipped,
                    footer: "같은 시각·같은 금액의 거래가 이미 있어서 넣지 않아요.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [StatementMatch], footer: String) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { match in
                    row(match)
                }
            } header: {
                Text("\(title) \(items.count)")
            } footer: {
                Text(footer)
            }
        }
    }

    private func row(_ match: StatementMatch) -> some View {
        Button {
            guard !match.alreadyImported, !match.candidates.isEmpty else { return }
            picking = match
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                HStack(spacing: DS.Spacing.small) {
                    Text(match.line.datetime.koreanShortDateString)
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.secondary)
                    Text(match.line.description ?? match.line.type)
                        .rowTitle()
                        .lineLimit(1)
                    Spacer(minLength: DS.Spacing.small)
                    Text("\(match.line.amount.formatted())원")
                        .typeStyle(DS.Typo.body2)
                        .tabularAmount()
                        .foregroundColor(match.line.amount > 0 ? DS.Palette.deposit : DS.Ink.primary)
                }

                if let group = match.chosen {
                    // 장부에 실제로 적힐 줄들. **이게 이 화면의 요점이다** —
                    // "이충성 −946,501" 이 아니라 "아침식사 414,000 …" 이 장부에 남는다.
                    ForEach(Array(group.ledgerLines.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: DS.Spacing.tight) {
                            Text("·")
                            Text(line.title).lineLimit(1)
                            Spacer(minLength: DS.Spacing.tight)
                            Text("\(line.amount.formatted())원").tabularAmount()
                        }
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.secondary)
                    }
                } else if !match.candidates.isEmpty {
                    Text("청구 묶음 \(match.candidates.count)개가 금액이 같아요")
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Palette.pending)
                }
            }
            .padding(.vertical, DS.Spacing.s1 / 2)
            .opacity(match.alreadyImported ? DS.State.disabledOpacity : 1)
        }
        .buttonStyle(.plain)
        .disabled(match.alreadyImported || match.candidates.isEmpty)
    }

    private func runImport() {
        Task {
            isImporting = true
            await viewModel.importStatement(matches, into: account)
            isImporting = false
            dismiss()
        }
    }
}

/// 금액이 같은 청구 묶음이 여럿일 때 사람이 고르는 시트.
///
/// **"청구 없이 넣기" 도 답이다.** 금액이 우연히 같을 뿐 관계없는 거래일 수 있다.
private struct CandidatePickerView: View {
    let match: StatementMatch
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(match.candidates) { group in
                        Button {
                            onPick(group.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                                HStack {
                                    Text(group.submitterName).rowTitle()
                                    Spacer()
                                    if group.id == match.chosenId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(DS.Ink.brand)
                                    }
                                }
                                Text("\(group.processedAt.koreanDateTimeString) 승인 · \(group.bills.count)건")
                                    .rowSubtext()
                                ForEach(Array(group.ledgerLines.enumerated()), id: \.offset) { _, line in
                                    Text("· \(line.title) \(line.amount.formatted())원")
                                        .typeStyle(DS.Typo.body3)
                                        .foregroundColor(DS.Ink.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("금액이 같은 청구 묶음")
                }

                Section {
                    Button("청구 없이 넣기") {
                        onPick(nil)
                        dismiss()
                    }
                } footer: {
                    Text("금액이 우연히 같을 뿐 관계없는 거래라면 이쪽이에요. 적요는 나중에 손으로 적으면 돼요.")
                }
            }
            .navigationTitle(match.line.description ?? "거래")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
