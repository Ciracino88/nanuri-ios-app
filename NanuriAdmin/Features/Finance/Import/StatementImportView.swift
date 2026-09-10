import SwiftUI

/// 거래내역서를 장부에 넣기 전에 **사람이 확인하는 풀스크린 화면.**
///
/// 예전에는 불러오기를 누르면 곧바로 저장했다. 그때는 앱이 통장을 베끼는 게 전부라
/// 확인할 것이 없었는데, 이제는 **청구서와 맞춰 적요·분할까지 만들어 낸다.**
/// 기계가 지어낸 이름이 장부에 그대로 들어가면 안 되므로 한 번 보여준다.
///
/// **목록은 "생성된 청구 내역"이다** — 은행 거래가 아니라 장부에 들어갈 항목을
/// 한 줄씩 보여준다(묶음은 조각마다 한 줄). 영수증이 있으면 아이콘 자리에 썸네일이
/// 뜬다. 행을 누르면 **청구 정보 / 영수증** 탭 상세로 들어간다.
///
/// **시각 언어는 재정 탭과 다르다** — 영수증 썸네일·상태 라벨·묶음 보라·합계 검산은
/// 사용자가 제시한 레퍼런스에서 왔고, DESIGN.md §13 에 **문서화된 예외**로 적혀 있다.
/// 불러오기 계열 화면에만 쓴다. 아이콘은 이모지가 아니라 SF Symbols 다(§6).
struct StatementImportView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let url: URL
    /// 이 내역서가 어느 통장 것인가. 토스에서 뽑으므로 모임통장이다.
    let account: Account

    @Environment(\.dismiss) private var dismiss

    @State private var matches: [StatementMatch] = []
    @State private var isPreparing = true
    @State private var isImporting = false
    /// 눌러서 들어간 항목의 키 "matchId#index". (`navigationDestination(item:)` 은
    /// Hashable 을 요구해 값이 아니라 키를 넘긴다.)
    @State private var openedKey: String?
    @State private var showCloseConfirm = false
    /// 방향 필터. 0 전체 · 1 출금 · 2 입금. **칩은 보는 렌즈일 뿐** — 넣는 건 늘 전체다.
    @State private var direction = 0

    // MARK: 데이터

    private var importing: [StatementMatch] { matches.filter { !$0.alreadyImported } }
    private var skippedCount: Int { matches.filter { $0.alreadyImported }.count }

    /// 생성될 항목 전부를 (거래, 조각) 쌍으로 편다.
    private var allItems: [StatementFlatRow] {
        importing.flatMap { m in m.previewItems.map { StatementFlatRow(match: m, preview: $0) } }
    }
    private func inDirection(_ r: StatementFlatRow) -> Bool {
        switch direction {
        case 1: return !r.preview.isInternalTransfer && r.match.line.amount < 0
        case 2: return !r.preview.isInternalTransfer && r.match.line.amount > 0
        default: return true
        }
    }
    /// 화면에 그릴 행들. 방향 필터 + 손댈 것 위로 정렬.
    private var rows: [StatementFlatRow] {
        allItems.filter(inDirection)
            .sorted { a, b in
                let pa = statusPriority(a.match), pb = statusPriority(b.match)
                if pa != pb { return pa < pb }
                return a.match.line.datetime < b.match.line.datetime
            }
    }
    private var outCount: Int { allItems.filter { !$0.preview.isInternalTransfer && $0.match.line.amount < 0 }.count }
    private var inCount: Int { allItems.filter { !$0.preview.isInternalTransfer && $0.match.line.amount > 0 }.count }
    private var importCount: Int { allItems.count }
    private var needsChoiceCount: Int {
        matches.filter { !$0.alreadyImported && !$0.isInternalTransfer
                         && $0.chosenId == nil && !$0.candidates.isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    if !isPreparing && !matches.isEmpty {
                        ChipSelector(items: [
                            .init(value: 0, label: "전체", count: importCount),
                            .init(value: 1, label: "출금", count: outCount),
                            .init(value: 2, label: "입금", count: inCount),
                        ], selection: $direction)
                        .padding(.bottom, DS.Spacing.medium)
                    }
                }
                .background(DS.Surface.card)

                bodyContent
            }
            .safeAreaInset(edge: .bottom) {
                if !isPreparing && !matches.isEmpty { importBar }
            }
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled()
            .confirmationDialog("넣지 않고 닫을까요?", isPresented: $showCloseConfirm, titleVisibility: .visible) {
                Button("닫기", role: .destructive) { dismiss() }
                Button("계속 보기", role: .cancel) {}
            } message: {
                Text("이 거래내역서는 앱에 보관하지 않아요. 다시 넣으려면 파일 앱에서 한 번 더 공유하면 돼요.")
            }
            .navigationDestination(item: $openedKey) { key in
                if let (m, idx) = resolve(key) {
                    StatementItemDetailView(match: m, focusIndex: idx,
                                            accountName: account.name,
                                            counterAccountName: counterName(m),
                                            categorySuggestions: viewModel.usedCategories) { updated in
                        if let i = matches.firstIndex(where: { $0.id == updated.id }) {
                            matches[i] = updated
                        }
                    }
                }
            }
            .task {
                matches = await viewModel.prepareStatementImport(from: url)
                isPreparing = false
            }
        }
    }

    private func resolve(_ key: String) -> (StatementMatch, Int)? {
        guard let hash = key.lastIndex(of: "#"),
              let idx = Int(key[key.index(after: hash)...]) else { return nil }
        let mid = String(key[..<hash])
        guard let m = matches.first(where: { $0.id == mid }) else { return nil }
        return (m, idx)
    }

    @ViewBuilder
    private var bodyContent: some View {
        Group {
            if isPreparing {
                ProgressView("맞춰 보는 중…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty {
                EmptyStateView(title: "읽어낸 거래가 없어요", icon: "doc.richtext")
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Surface.page)
    }

    private var header: some View {
        AdminHeaderView(
            showsNotifications: false,
            center: { Text("청구 내역 확인").headerTitle() },
            leading: {
                Button("닫기") { closeRequested() }
                    .typeStyle(DS.Typo.labelM)
                    .foregroundColor(DS.Ink.primary)
                    .padding(.horizontal, DS.Spacing.small)
                    .disabled(isImporting)
            },
            trailing: { EmptyView() }
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("생성된 청구 내역").typeStyle(DS.Typo.title2).foregroundColor(DS.Ink.primary)
                        Spacer()
                        Text("\(rows.count)건").typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.placeholder)
                    }
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.top, DS.Spacing.medium)
                    .padding(.bottom, DS.Spacing.small)

                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, r in
                        row(r.match, r.preview, first: offset == 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Surface.card)

                if skippedCount > 0 {
                    Text("이미 장부에 있는 \(skippedCount)건은 뺐어요.")
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.tertiary)
                        .padding(.horizontal, DS.Spacing.screen)
                        .padding(.vertical, DS.Spacing.medium)
                }
            }
            .padding(.bottom, DS.Spacing.s8)
            .animation(DS.Motion.list, value: direction)
        }
    }

    // MARK: 한 줄 (= 생성될 항목 하나)

    private func row(_ m: StatementMatch, _ p: StatementMatch.Preview, first: Bool) -> some View {
        let (statusText, statusColor) = statusStyle(m)
        return Button {
            openedKey = "\(m.id)#\(p.index)"
        } label: {
            HStack(spacing: DS.Spacing.medium) {
                thumbnail(p)

                VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                    // 묶음 여부는 오른쪽 상태 라벨('묶음 매칭')이 이미 말한다 — 적요 옆
                    // 라벨·썸네일 아이콘까지 두면 한 줄에 묶음 신호가 셋이라 과하다.
                    Text(p.title).rowTitle().lineLimit(1)
                    Text(subtitle(m, p)).typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.secondary).lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.small)

                VStack(alignment: .trailing, spacing: DS.Spacing.s1 / 2) {
                    Text(amountText(m, p)).typeStyle(DS.Typo.amount).tabularAmount()
                        .foregroundColor(amountColor(m, p))
                    Text(statusText).typeStyle(DS.Typo.caption).foregroundColor(statusColor)
                }

                Image(systemName: "chevron.right")
                    .font(DS.Icon.font(DS.Icon.s)).foregroundColor(DS.Ink.placeholder)
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if !first {
                    Rectangle().fill(DS.Line.default).frame(height: DS.Line.hairline)
                        .padding(.leading, DS.Spacing.screen)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 영수증 썸네일 또는 카메라 자리표시.
    private func thumbnail(_ p: StatementMatch.Preview) -> some View {
        Group {
            if let urlStr = p.receiptUrls.first, let u = URL(string: urlStr) {
                RemoteImage(url: u, maxDimension: DS.Size.rowAvatar * 2) {
                    Rectangle().fill(DS.Surface.secondary)
                } failure: {
                    cameraTile
                }
                .scaledToFill()
                .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
            } else {
                cameraTile
            }
        }
        .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
    }

    private var cameraTile: some View {
        RoundedRectangle(cornerRadius: DS.Radius.m)
            .strokeBorder(style: StrokeStyle(lineWidth: DS.Line.focusedWidth, dash: [4]))
            .foregroundColor(DS.Ink.placeholder)
            .background(DS.Surface.secondary.clipShape(RoundedRectangle(cornerRadius: DS.Radius.m)))
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
            .overlay(
                Image(systemName: "camera")
                    .font(DS.Icon.font(DS.Icon.m))
                    .foregroundColor(DS.Ink.placeholder)
            )
    }

    // MARK: 줄 스타일

    private enum StatusKind { case needsChoice, matched, unmatched, transfer }
    private func statusKind(_ m: StatementMatch) -> StatusKind {
        if m.isInternalTransfer { return .transfer }
        if m.chosenId != nil { return .matched }
        if !m.candidates.isEmpty { return .needsChoice }
        return .unmatched
    }
    private func statusPriority(_ m: StatementMatch) -> Int {
        switch statusKind(m) { case .needsChoice: return 0; case .unmatched: return 1
                               case .matched: return 2; case .transfer: return 3 }
    }
    private func isGroup(_ m: StatementMatch) -> Bool {
        m.chosenId != nil && m.previewItems.count > 1
    }
    private func statusStyle(_ m: StatementMatch) -> (String, Color) {
        switch statusKind(m) {
        case .needsChoice: return ("확인 필요", DS.Palette.pending)
        case .matched: return isGroup(m) ? ("묶음 매칭", DS.Palette.group) : ("청구 맞음", DS.Palette.accent)
        case .unmatched: return ("청구 없음", DS.Ink.tertiary)
        case .transfer: return ("통장 이체", DS.Ink.tertiary)
        }
    }
    private func subtitle(_ m: StatementMatch, _ p: StatementMatch.Preview) -> String {
        let date = m.line.datetime.koreanShortDateString
        if p.isInternalTransfer { return "\(date) · 합계에서 빠져요" }
        // 카테고리는 안 보인다 — 불러온 직후엔 전부 미분류라 알려 줄 게 없다.
        var parts = [date]
        if let s = m.chosen?.submitterName, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: " · ")
    }
    private func amountText(_ m: StatementMatch, _ p: StatementMatch.Preview) -> String {
        let mag = p.amount.formatted()
        return (!p.isInternalTransfer && m.line.amount > 0) ? "+\(mag)원" : "\(mag)원"
    }
    private func amountColor(_ m: StatementMatch, _ p: StatementMatch.Preview) -> Color {
        if p.isInternalTransfer { return DS.Ink.tertiary }
        return m.line.amount > 0 ? DS.Palette.deposit : DS.Palette.withdrawal
    }

    // MARK: 바닥 바

    private var importBar: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            // 건수·합계는 두지 않는다 — 건수는 "생성된 청구 내역 N건" 머리가 이미 말하고,
            // 합계는 입금·출금·이체를 섞은 값이라 뜻이 흐렸다. 미결정 알림만 남긴다.
            if needsChoiceCount > 0 {
                Text("\(needsChoiceCount)건은 어느 청구인지 아직 안 정했어요")
                    .typeStyle(DS.Typo.body3).foregroundColor(DS.Palette.pending)
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
        .background(DS.Surface.card)
        .elevation(.bottomBar)
    }

    // MARK: 동작

    private func counterName(_ match: StatementMatch) -> String {
        viewModel.accounts.first { $0.id != account.id }?.name ?? ""
    }
    private func closeRequested() {
        if importCount > 0 { showCloseConfirm = true } else { dismiss() }
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
