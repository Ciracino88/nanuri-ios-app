import SwiftUI

// MARK: - 상세 (청구 정보 / 영수증 탭)

/// 생성될 항목 하나의 **상세 + 편집.** 레퍼런스 `BillingDetailScreen` 문법.
///
/// 두 탭 — **청구 정보**(① 청구 내역·금액 ② 상세 정보 ③ 매칭된 은행 거래)와 **영수증**.
/// 편집(청구 선택 · 적요 · 카테고리 · 이체 토글)이 청구 정보 탭에 있고, **나갈 때
/// 저장된다**(`onDisappear`).
struct StatementItemDetailView: View {
    let match: StatementMatch
    /// 이 상세가 보는 조각의 인덱스.
    let focusIndex: Int
    let accountName: String
    let counterAccountName: String
    let categorySuggestions: [String]
    let onSave: (StatementMatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: StatementMatch
    @State private var tab = 0   // 0 청구 정보 · 1 영수증
    @State private var zoom: ReceiptPreview?

    init(match: StatementMatch, focusIndex: Int, accountName: String,
         counterAccountName: String, categorySuggestions: [String],
         onSave: @escaping (StatementMatch) -> Void) {
        self.match = match
        self.focusIndex = focusIndex
        self.accountName = accountName
        self.counterAccountName = counterAccountName
        self.categorySuggestions = categorySuggestions
        self.onSave = onSave
        var m = match
        // 항목별 카테고리 편집을 위해 배열을 조각 수만큼 채워 둔다.
        let n = m.previewItems.count
        if m.itemCategories.count < n {
            m.itemCategories.append(contentsOf: Array(repeating: "", count: n - m.itemCategories.count))
        }
        _draft = State(initialValue: m)
    }

    private var items: [StatementMatch.Preview] { draft.previewItems }
    private var item: StatementMatch.Preview {
        items.indices.contains(focusIndex) ? items[focusIndex] : (items.first ?? StatementMatch.Preview(index: 0, title: "", amount: 0, category: nil, receiptUrls: [], isInternalTransfer: false))
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            segments
            ScrollView {
                if tab == 0 { infoTab } else { receiptTab }
            }
            .background(tab == 0 ? DS.Surface.page : Color.black)
        }
        .background(tab == 0 ? DS.Surface.page : Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $zoom) { p in ReceiptViewerView(source: p.source) }
        .onDisappear { onSave(draft) }
    }

    private var detailHeader: some View {
        AdminHeaderView(
            showsNotifications: false,
            center: { Text("청구 상세").headerTitle() },
            leading: { HeaderBackButton { dismiss() } },
            trailing: { EmptyView() }
        )
        .background(DS.Surface.card)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            segButton("청구 정보", 0)
            segButton("영수증", 1)
        }
        .background(DS.Surface.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Line.default).frame(height: DS.Line.hairline)
        }
    }
    private func segButton(_ title: String, _ i: Int) -> some View {
        let on = tab == i
        return Button { withAnimation(DS.Motion.control) { tab = i } } label: {
            Text(title)
                .typeStyle(on ? DS.Typo.labelM : DS.Typo.body2)
                .foregroundColor(on ? DS.Ink.primary : DS.Ink.placeholder)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.medium)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? DS.Ink.primary : .clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 청구 정보 탭

    private var infoTab: some View {
        LazyVStack(spacing: DS.Spacing.cardGap) {
            heroCard                                   // ① 청구 내역 + 금액
            if !draft.isInternalTransfer { infoCard }  // ② 상세 정보
            thirdSection                               // ③ 매칭된 은행 거래 / 후보 / 이체
        }
        .padding(.vertical, DS.Spacing.cardGap)
    }

    // ① hero
    private var heroCard: some View {
        VStack(spacing: DS.Spacing.tight) {
            statusPill
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                Text(item.amount.formatted()).heroAmount().tabularAmount()
                    .foregroundColor(draft.isInternalTransfer ? DS.Ink.tertiary : DS.Ink.primary)
                Text("원").amountUnit()
            }
            Text(item.title.isEmpty ? "적요 없음" : item.title)
                .typeStyle(DS.Typo.body2).foregroundColor(DS.Ink.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sheetEdge)
        .padding(.horizontal, DS.Spacing.screen)
        .background(DS.Surface.card)
    }

    @ViewBuilder private var statusPill: some View {
        let (text, tone) = pillStyle
        Text(text).typeStyle(DS.Typo.labelS).foregroundColor(tone.content)
            .padding(.horizontal, DS.Spacing.medium).padding(.vertical, DS.Spacing.small)
            .background(tone.surface).clipShape(Capsule())
            .padding(.bottom, DS.Spacing.small)
    }
    private var pillStyle: (String, DS.ColorTone) {
        if draft.isInternalTransfer { return ("통장 사이 이체", DS.Tone.neutral) }
        if draft.chosenId != nil { return items.count > 1 ? ("묶음 매칭", DS.Tone.group) : ("청구 맞음", DS.Tone.brand) }
        if !match.candidates.isEmpty { return ("확인 필요", DS.Tone.pending) }
        return ("청구 없음", DS.Tone.neutral)
    }

    // ② 상세 정보
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 라벨은 살짝 힘을 준다(세미볼드). 아래에 구분선은 두지 않는다 —
            // 첫 행이 자기 위 구분선을 그리지 않는다(`divider: false`).
            Text("청구 정보").typeStyle(DS.Typo.labelS).foregroundColor(DS.Ink.secondary)
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.s4).padding(.bottom, DS.Spacing.s5)

            // 청구 내역 — 청구를 고른 항목은 청구 제목이라 고정, 아니면 적요를 적는다.
            if draft.chosen == nil {
                NavigationLink {
                    ImportTextPage(title: "적요",
                                   placeholder: match.line.description ?? "적요",
                                   text: $draft.manualDescription)
                } label: {
                    infoRow("청구 내역", value: item.title.isEmpty ? "없음" : item.title,
                            empty: item.title.isEmpty, chevron: true, divider: false)
                }
                .buttonStyle(.plain)
            } else {
                infoRow("청구 내역", value: item.title, empty: false, chevron: false, divider: false)
            }

            // 카테고리 — 없으면 '없음' + 셰브런으로 입력 페이지.
            if focusIndex < draft.itemCategories.count {
                NavigationLink {
                    ImportCategoryPage(suggestions: categorySuggestions,
                                       text: $draft.itemCategories[focusIndex])
                } label: {
                    infoRow("카테고리", value: item.category ?? "없음",
                            empty: item.category == nil, chevron: true)
                }
                .buttonStyle(.plain)
            }

            infoRow("청구자", value: match.chosen?.submitterName ?? "—",
                    empty: match.chosen == nil, chevron: false)

            infoRow("날짜", value: match.line.datetime.koreanShortDateString,
                    empty: false, chevron: false)

            // 영수증 — 있으면 썸네일 + 영수증 탭으로, 없으면 '없음'.
            Button { if !item.receiptUrls.isEmpty { withAnimation(DS.Motion.control) { tab = 1 } } } label: {
                HStack {
                    Text("영수증").typeStyle(DS.Typo.body2).foregroundColor(DS.Ink.secondary)
                    Spacer()
                    if let urlStr = item.receiptUrls.first, let u = URL(string: urlStr) {
                        RemoteImage(url: u, maxDimension: 68) {
                            Rectangle().fill(DS.Surface.secondary)
                        } failure: {
                            Rectangle().fill(DS.Surface.secondary)
                        }
                        .scaledToFill().frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
                        Image(systemName: "chevron.right").font(DS.Icon.font(DS.Icon.s))
                            .foregroundColor(DS.Ink.placeholder)
                    } else {
                        Text("없음").typeStyle(DS.Typo.body2).foregroundColor(DS.Ink.placeholder)
                    }
                }
                .padding(.horizontal, DS.Spacing.screen).padding(.vertical, DS.Spacing.s4)
                .contentShape(Rectangle())
                .overlay(alignment: .top) { rowLine }
            }
            .buttonStyle(.plain)
            .disabled(item.receiptUrls.isEmpty)
        }
        .padding(.bottom, DS.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
    }

    private func infoRow(_ label: String, value: String, empty: Bool, chevron: Bool,
                         divider: Bool = true) -> some View {
        HStack {
            Text(label).typeStyle(DS.Typo.body2).foregroundColor(DS.Ink.secondary)
            Spacer(minLength: DS.Spacing.small)
            Text(value).typeStyle(DS.Typo.labelM)
                .foregroundColor(empty ? DS.Ink.placeholder : DS.Ink.primary)
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right").font(DS.Icon.font(DS.Icon.s))
                    .foregroundColor(DS.Ink.placeholder)
            }
        }
        .padding(.horizontal, DS.Spacing.screen).padding(.vertical, DS.Spacing.s4)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if divider { rowLine } }
    }
    private var rowLine: some View {
        Rectangle().fill(DS.Line.default).frame(height: DS.Line.hairline)
            .padding(.leading, DS.Spacing.screen)
    }

    // ③ 매칭된 은행 거래 / 후보 고르기 / 이체
    @ViewBuilder private var thirdSection: some View {
        if draft.isInternalTransfer {
            transferCard
        } else if draft.chosenId != nil {
            matchedBankCard
        } else if !match.candidates.isEmpty {
            candidateCard
        } else {
            noMatchCard
        }
    }

    private var matchedBankCard: some View {
        let lines = draft.chosen?.ledgerLines ?? []
        let sum = lines.reduce(0) { $0 + $1.amount }
        let ok = sum == abs(match.line.amount)
        return VStack(alignment: .leading, spacing: 0) {
            cardHeader("매칭된 은행 거래")
            HStack(spacing: DS.Spacing.medium) {
                Image(systemName: lines.count > 1 ? "shippingbox" : "arrow.up.circle")
                    .font(DS.Icon.font(DS.Icon.action)).foregroundColor(DS.Tone.group.content)
                    .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
                    .background(DS.Tone.group.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.line.description ?? match.line.type).rowTitle().lineLimit(1)
                    Text("\(accountName)통장 · \(match.line.datetime.koreanShortDateString)")
                        .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.secondary)
                }
                Spacer()
                Text("\(abs(match.line.amount).formatted())원")
                    .typeStyle(DS.Typo.amount).tabularAmount().foregroundColor(DS.Ink.primary)
            }
            .padding(DS.Spacing.s4)
            .background(DS.Surface.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
            .padding(.horizontal, DS.Spacing.screen)

            if lines.count > 1 {
                Text("이 거래에 포함된 청구 \(lines.count)건")
                    .typeStyle(DS.Typo.labelS).foregroundColor(DS.Ink.secondary)
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.top, DS.Spacing.s4).padding(.bottom, DS.Spacing.s5)
                VStack(spacing: DS.Spacing.small) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        includedCard(i: i, title: line.title, amount: line.amount, isSelf: i == focusIndex)
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)

                checksum(sum: sum, count: lines.count, ok: ok)
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.top, DS.Spacing.medium).padding(.bottom, DS.Spacing.s5)
            } else {
                Spacer().frame(height: DS.Spacing.s5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
    }

    private func includedCard(i: Int, title: String, amount: Int, isSelf: Bool) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            Text("\(i + 1)")
                .typeStyle(DS.Typo.labelS)
                .foregroundColor(isSelf ? DS.Tone.group.content : DS.Ink.secondary)
                .frame(width: 26, height: 26)
                .background(isSelf ? DS.Tone.group.surface : DS.Surface.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s))
            Text(title).typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.primary).lineLimit(1)
            if isSelf {
                Text("현재 항목").typeStyle(DS.Typo.captionS).foregroundColor(DS.Tone.group.content)
            }
            Spacer(minLength: DS.Spacing.small)
            Text("\(amount.formatted())원").typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.primary).tabularAmount()
        }
        .padding(DS.Spacing.s4)
        .background(isSelf ? DS.Tone.group.surface : DS.Surface.secondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
    }

    private func checksum(sum: Int, count: Int, ok: Bool) -> some View {
        let tone = ok ? DS.Tone.done : DS.Tone.danger
        return HStack(spacing: DS.Spacing.small) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(DS.Icon.font(DS.Icon.m)).foregroundColor(tone.content)
            VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                Text(ok ? "합계 일치" : "합계가 안 맞아요").typeStyle(DS.Typo.labelS).foregroundColor(tone.content)
                Text("청구 \(count)건의 합산").typeStyle(DS.Typo.captionS).foregroundColor(tone.content)
            }
            Spacer()
            Text("\(sum.formatted())원").typeStyle(DS.Typo.labelM).foregroundColor(tone.content).tabularAmount()
        }
        .padding(DS.Spacing.s4).background(tone.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
    }

    private var candidateCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            cardHeader("금액이 같은 청구 묶음")
            ForEach(match.candidates) { group in
                candidateRow(group.submitterName,
                             sub: "\(group.processedAt.koreanDateTimeString) 승인 · \(group.bills.count)건",
                             selected: group.id == draft.chosenId) { draft.chosenId = group.id }
            }
            candidateRow("청구 없이 넣기", sub: nil, selected: draft.chosenId == nil) { draft.chosenId = nil }
            Text("금액이 우연히 같을 뿐 관계없는 거래라면 '청구 없이 넣기' 예요.")
                .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.tertiary)
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.tight)
        }
        .padding(.bottom, DS.Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
    }
    private func candidateRow(_ title: String, sub: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                    Text(title).rowTitle()
                    if let sub { Text(sub).typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.secondary) }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(DS.Icon.font(DS.Icon.m)).foregroundColor(DS.Ink.brand)
                }
            }
            .padding(DS.Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Surface.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.screen)
    }

    private var noMatchCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            cardHeader("매칭된 청구")
            Text("맞는 청구가 없어 은행 적요 그대로 들어가요. 위에서 적요와 카테고리를 적을 수 있어요.")
                .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.tertiary)
                .padding(.horizontal, DS.Spacing.screen)
        }
        .padding(.bottom, DS.Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
    }

    private var transferCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            cardHeader("통장 사이 이체")
            Toggle(isOn: $draft.isInternalTransfer) { Text("통장 사이 이체").rowTitle() }
                .tint(DS.Palette.accent)
                .padding(.horizontal, DS.Spacing.screen)
            Text("\(counterAccountName) 통장과 주고받은 돈이에요. 활성화 시, 입출금 내역에 반영하지 않습니다.")
                .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.tertiary)
                .padding(.horizontal, DS.Spacing.screen)
        }
        .padding(.bottom, DS.Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Surface.card)
    }

    private func cardHeader(_ title: String) -> some View {
        Text(title).typeStyle(DS.Typo.labelS).foregroundColor(DS.Ink.secondary)
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.s4).padding(.bottom, DS.Spacing.s5)
    }

    // MARK: 영수증 탭

    @ViewBuilder private var receiptTab: some View {
        if item.receiptUrls.isEmpty {
            VStack(spacing: DS.Spacing.medium) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: DS.Icon.placeholder)).foregroundColor(DS.Ink.placeholder)
                Text("이 청구에는 영수증이 없어요")
                    .typeStyle(DS.Typo.labelM).foregroundColor(DS.Ink.placeholder)
            }
            .frame(maxWidth: .infinity).padding(.top, DS.Spacing.s16)
        } else {
            VStack(spacing: DS.Spacing.medium) {
                ForEach(Array(item.receiptUrls.enumerated()), id: \.offset) { _, urlStr in
                    Button { zoom = ReceiptPreview(source: .remote(urlStr)) } label: {
                        RemoteImage(url: URL(string: urlStr), maxDimension: DS.Size.fullPhoto) {
                            ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: 200)
                        } failure: {
                            Text("영수증을 불러오지 못했어요").typeStyle(DS.Typo.body2).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 120)
                        }
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Spacing.screen)
        }
    }
}
