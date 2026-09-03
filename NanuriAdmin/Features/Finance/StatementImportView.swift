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
    /// 공유로 들어온 파일. **앱은 이걸 보관하지 않는다** — 이 화면이 닫히면 끝이고,
    /// 다시 필요하면 파일 앱에서 다시 공유한다.
    let url: URL
    /// 이 내역서가 어느 통장 것인가. 토스에서 뽑으므로 모임통장이다.
    let account: Account

    @Environment(\.dismiss) private var dismiss

    @State private var matches: [StatementMatch] = []
    @State private var isPreparing = true
    @State private var isImporting = false
    @State private var picking: StatementMatch?
    @State private var showCloseConfirm = false
    /// "이미 장부에 있어요" 는 접어 둔다. 같은 달을 다시 뽑으면 **그 섹션이 제일
    /// 길어서**, 펼쳐 두면 정작 손댈 줄이 화면 밖으로 밀린다.
    @State private var showSkipped = false

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
    private var importing: [StatementMatch] { matches.filter { !$0.alreadyImported } }
    private var importCount: Int { importing.count }
    private var importTotal: Int { importing.reduce(0) { $0 + $1.line.amount } }

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
            // 목록이 흰 바탕에 그냥 앉는 구조라 재정 탭과 같은 흰 페이지다.
            .screenBackground(DS.Surface.card)
            .navigationTitle("거래내역서 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { closeRequested() }.disabled(isImporting)
                }
            }
            // 결정은 바닥이다. 오른쪽 위 작은 글자에 두면 이 화면의 유일한 행동이
            // 가장 안 눌리는 자리에 앉는다 (DESIGN.md 8번).
            .safeAreaInset(edge: .bottom) {
                if !isPreparing && !matches.isEmpty { importBar }
            }
            // 넣기 전에 닫으면 이 파일은 사라진다 (보관하지 않는다). 쓸어내려
            // 닫는 것도 막고 닫기 버튼 하나로 모은다 — 그래야 물어볼 자리가 생긴다.
            .interactiveDismissDisabled()
            .confirmationDialog("넣지 않고 닫을까요?", isPresented: $showCloseConfirm, titleVisibility: .visible) {
                Button("닫기", role: .destructive) { dismiss() }
                Button("계속 보기", role: .cancel) {}
            } message: {
                Text("이 거래내역서는 앱에 보관하지 않아요. 다시 넣으려면 파일 앱에서 한 번 더 공유하면 돼요.")
            }
            .sheet(item: $picking) { match in
                CandidatePickerView(match: match) { chosenId in
                    if let idx = matches.firstIndex(where: { $0.id == match.id }) {
                        matches[idx].chosenId = chosenId
                    }
                }
            }
            .task {
                matches = await viewModel.prepareStatementImport(from: url)
                isPreparing = false
            }
        }
    }

    /// `List` 가 아니라 `ScrollView` 다 — 재정 탭 목록과 같은 문법이다.
    /// **섹션은 회색 소제목이 앉고 그 아래 줄이 흰 바탕 위에 바로 놓인다.**
    /// 상자도 구분선도 없다 (DESIGN.md 1번 "카드냐 섹션이냐").
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                section("확인이 필요해요", needsChoice)
                section("청구서와 맞았어요", matched)
                section("청구 없이 넣어요", unmatched,
                        note: "적요와 분류는 넣은 뒤에 손으로 적으면 돼요.")
                skippedSection
            }
            .padding(.bottom, DS.Spacing.s8)
            .animation(DS.Motion.list, value: showSkipped)
        }
    }

    /// 섹션 하나. `note` 는 **읽어야 알 수 있는 것만** 준다.
    ///
    /// 예전에는 네 섹션 전부 두 줄짜리 설명이 붙어서 설명이 항목보다 많았다.
    /// 지금은 줄 자체가 말하는 것(후보가 몇 개인지, 장부에 뭐라고 적힐지)은 빼고,
    /// 줄을 봐도 모르는 것만 남긴다.
    @ViewBuilder
    private func section(_ title: String, _ items: [StatementMatch], note: String? = nil) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title, count: items.count)
                if let note {
                    Text(note)
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.tertiary)
                        .padding(.horizontal, DS.Spacing.s4)
                        .padding(.bottom, DS.Spacing.small)
                }
                ForEach(items) { match in
                    row(match)
                }
            }
        }
    }

    /// 이미 넣은 것들. **접어 둔다.**
    @ViewBuilder
    private var skippedSection: some View {
        if !skipped.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(DS.Motion.control) { showSkipped.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.tight) {
                        sectionHeader("이미 장부에 있어요", count: skipped.count)
                        Image(systemName: showSkipped ? "chevron.up" : "chevron.down")
                            .font(DS.Icon.font(DS.Icon.m))
                            .foregroundColor(DS.Ink.placeholder)
                            .padding(.top, DS.Spacing.s6)
                            .padding(.bottom, DS.Spacing.medium)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showSkipped {
                    ForEach(skipped) { match in
                        row(match)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) \(count)")
            .typeStyle(DS.Typo.body3)
            .foregroundColor(DS.Ink.secondary)
            .padding(.horizontal, DS.Spacing.s4)
            .padding(.top, DS.Spacing.s6)
            .padding(.bottom, DS.Spacing.medium)
    }

    /// 바닥 바. **건수·합계와 결정을 한 자리에 담는다** — 묶어 보내기의
    /// `selectionBar` 와 같은 문법이다.
    private var importBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                if !needsChoice.isEmpty {
                    // 막지는 않는다. 안 정한 채로 넣으면 청구 없이 들어갈 뿐이라
                    // 되돌릴 수 있고, 넣기를 잠그면 빠져나갈 길이 없어진다.
                    Text("\(needsChoice.count)건은 어느 청구인지 아직 안 정했어요")
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Palette.pending)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(importCount == 0 ? "넣을 거래가 없어요" : "\(importCount)건 넣어요")
                        .rowTitle()
                    Spacer(minLength: DS.Spacing.small)
                    if importCount > 0 {
                        Text("\(importTotal.formatted())원")
                            .cardTitle()
                            .tabularAmount()
                    }
                }
                if isImporting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    ActionButton(title: "장부에 넣기", kind: .primary, action: runImport)
                        .disabled(importCount == 0)
                        .opacity(importCount == 0 ? DS.State.disabledOpacity : 1)
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.medium)
            .padding(.bottom, DS.Spacing.small)
        }
        .background(DS.Surface.card)
        .elevation(.bottomBar)
    }

    /// 한 줄. **누를 수 있는 줄에만 화살표를 준다** — 네 섹션이 겉으로 같아 보이면
    /// 어디를 눌러 고칠 수 있는지 알 길이 없다. 화살표가 없으면 읽는 줄이다.
    private func row(_ match: StatementMatch) -> some View {
        let canPick = !match.alreadyImported && !match.candidates.isEmpty
        return Button {
            guard canPick else { return }
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
                    if canPick {
                        Image(systemName: "chevron.right")
                            .font(DS.Icon.font(DS.Icon.m))
                            .foregroundColor(DS.Ink.placeholder)
                    }
                }

                if let group = match.chosen {
                    // 장부에 실제로 적힐 줄들. **이게 이 화면의 요점이다** —
                    // "홍길동 −946,501" 이 아니라 "아침식사 414,000 …" 이 장부에 남는다.
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
            .padding(.horizontal, DS.Spacing.s4)
            .padding(.vertical, DS.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(match.alreadyImported ? DS.State.disabledOpacity : 1)
        }
        .buttonStyle(.plain)
        .disabled(!canPick)
    }

    /// 넣을 게 남아 있으면 물어보고, 없으면 그냥 닫는다.
    /// **다 이미 장부에 있는 내역서**를 확인만 하고 닫는 건 잃는 게 없다.
    private func closeRequested() {
        if importCount > 0 {
            showCloseConfirm = true
        } else {
            dismiss()
        }
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
