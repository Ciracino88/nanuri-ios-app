import SwiftUI

/// 이 달을 지난달과 견주어 보는 화면. 요약 밴드의 "자세히 보기" 가 연다.
///
/// 밴드가 한 줄로 흘려 말한 것을 **크게 다시 말하고, 왜 그런지까지 붙인다.**
///
/// ```
/// 닫기 ✕                        ← 오른쪽 위. 상세 시트와 같은 자리다
/// 2026년 8월                     ← 어느 달인지. 여기서는 달을 넘기지 않는다
/// 지난달보다 62만원 더 나갔어요      ← 밴드와 **같은 문장**을 키운 것
///                    ● 8월 ● 7월  ← 두 선이 무엇인지
/// [두 선 그래프]  8.1 ── 8.31
/// ────────────────
/// 소비 분석
/// [출금 14] [입금 5]              ← 어느 쪽을 나눠 볼지
/// 헌금에 가장 많이 나갔어요
/// [비중 막대]
/// · 헌금 320,000원 · … · 그 외 8개
/// ```
///
/// **날짜 축과 거래 목록은 여기 없다.** 재정 탭 본화면이 이미 갖고 있어서, 여기
/// 또 넣으면 같은 것이 두 화면에 산다. 목록으로 돌아가는 길은 닫기다.
///
/// 달을 넘기는 자리도 없다. 이 화면은 **어느 한 달을 들고 들어오는** 곳이라,
/// 여기서 달이 바뀌면 뒤에 남겨 둔 목록과 어긋난다.
struct SpendingDetailView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let ledger: Ledger

    @Environment(\.dismiss) private var dismiss
    /// 0 이 출금, 1 이 입금. **출금이 먼저다** — 견주는 문장이 지출 이야기다.
    @State private var segment = 0

    private var isDeposit: Bool { segment == 1 }
    private var totals: [CategoryTotal] { viewModel.categoryTotals(deposit: isDeposit) }
    private var comparison: SpendingComparison { viewModel.comparison }

    var body: some View {
        VStack(spacing: 0) {
            closeBar

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    headline
                    if comparison.hasPrevious {
                        chart
                    }
                    Divider()
                    breakdown
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.sheetEdge)
            }
        }
        .presentationDetents([.large])
        .screenBackground(DS.Surface.card)
    }

    /// 오른쪽 위 ✕. 청구서 상세 시트와 같은 자리다 (`BillDetailView`).
    private var closeBar: some View {
        HStack {
            Spacer()
            HeaderIconButton(systemName: "xmark", label: "닫기") { dismiss() }
        }
        .padding(.horizontal, DS.Spacing.small)
    }

    // MARK: - 머리

    /// 어느 달인지 한 줄, 그 아래 견준 문장.
    ///
    /// 문장은 밴드가 쓰는 것과 **같은 `SpendingComparison`** 이다. 크기만 다르다 —
    /// 밴드에서는 곁다리였던 문장이 여기서는 화면의 제목이다.
    private var headline: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text(periodLabel)
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.secondary)

            comparison.text
                .typeStyle(DS.Typo.h2)
                .foregroundColor(DS.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Spacing.medium)
    }

    /// 월별 장부는 달 이름, 행사 장부는 행사 이름. 행사 통장에는 "이 달" 이 없다.
    private var periodLabel: String {
        ledger.mode == .monthly ? viewModel.currentMonth.koreanYearMonthString : ledger.name
    }

    // MARK: - 그래프

    private var chart: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            legend
            SpendingSparkline(
                current: viewModel.cumulativeWithdrawals(monthsAgo: 0),
                previous: viewModel.cumulativeWithdrawals(monthsAgo: 1),
                tint: comparison.color,
                scale: .expanded(start: axisStart, end: axisEnd)
            )
        }
    }

    /// 두 선이 무엇인지. **이 달 선의 색은 문장의 금액과 같다.**
    private var legend: some View {
        HStack(spacing: DS.Spacing.medium) {
            Spacer(minLength: 0)
            legendItem(color: comparison.color, label: monthLabel(monthsAgo: 0))
            legendItem(color: DS.Line.strong, label: monthLabel(monthsAgo: 1))
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: DS.Spacing.tight) {
            Capsule()
                .fill(color)
                .frame(width: DS.Spacing.medium, height: DS.Line.focusedWidth * 2)
            Text(label)
                .typeStyle(DS.Typo.captionS)
                .foregroundColor(DS.Ink.secondary)
        }
    }

    private func monthLabel(monthsAgo: Int) -> String {
        let cal = Calendar.current
        guard let month = cal.date(byAdding: .month, value: -monthsAgo, to: viewModel.currentMonth) else { return "" }
        return "\(cal.component(.month, from: month))월"
    }

    /// 가로 끝에 붙는 첫날·말일. 눈금이 아니라 **한 달치라는 것**을 말하는 라벨이다.
    private var axisStart: String {
        let cal = Calendar.current
        return "\(cal.component(.month, from: viewModel.currentMonth)).1"
    }

    private var axisEnd: String {
        let cal = Calendar.current
        let end = viewModel.endDate
        return "\(cal.component(.month, from: end)).\(cal.component(.day, from: end))"
    }

    // MARK: - 카테고리

    /// 어디에 많이 나갔는지. 카테고리를 입력받고 있으면서 지금까지 어디에서도
    /// 합쳐 보여주지 않던 값이다.
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s5) {
            Text("소비 분석")
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.secondary)

            // **입금도 나눠 본다.** 레퍼런스는 개인 소비라 지출만 보면 되지만,
            // 교회 장부는 헌금이 지출만큼 중요하다.
            PillPicker(tabs: [("출금", viewModel.withdrawals.count),
                              ("입금", viewModel.deposits.count)],
                       selection: $segment)

            if totals.isEmpty {
                Text(isDeposit ? "이 기간에는 입금이 없어요" : "이 기간에는 출금이 없어요")
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Spacing.s8)
            } else {
                topLine
                proportionBar
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        categoryRow(item, index: index)
                    }
                }
            }
        }
        .animation(DS.Motion.control, value: segment)
    }

    /// 1등을 문장으로 말한다. 이름만 색이 붙어 막대의 첫 칸과 묶인다.
    private var topLine: some View {
        let name = Text(totals[0].name).foregroundColor(DS.Palette.categorySeries[0])
        let tail = isDeposit ? "에서 가장 많이 들어왔어요" : "에 가장 많이 나갔어요"
        return Text("\(name)\(tail)")
            .typeStyle(DS.Typo.h4)
            .foregroundColor(DS.Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 비중 막대. **눈금도 값도 없다** — 어느 것이 큰지만 읽는 자리고,
    /// 정확한 수는 바로 아래 목록에 있다.
    private var proportionBar: some View {
        let segments = rows
        let total = max(segments.reduce(0) { $0 + $1.amount }, 1)
        let gap = DS.Spacing.tight
        return GeometryReader { geo in
            let usable = max(geo.size.width - gap * CGFloat(segments.count - 1), 1)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, item in
                    Capsule()
                        .fill(color(at: index))
                        // 아주 작은 조각도 자리를 갖는다. 폭이 0 이 되면 색만
                        // 남고 무엇의 조각인지 안 보인다.
                        .frame(width: max(gap, usable * CGFloat(item.amount) / CGFloat(total)))
                }
            }
        }
        .frame(height: DS.Size.barTrack)
        // 막대가 말하는 것은 아래 목록이 수로 다시 말한다.
        .accessibilityHidden(true)
    }

    private func categoryRow(_ item: CategoryTotal, index: Int) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            Circle()
                .fill(color(at: index))
                .frame(width: DS.Spacing.small, height: DS.Spacing.small)
            Text(item.name)
                .rowTitle()
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.small)
            Text("\(item.amount.formatted())원")
                .typeStyle(DS.Typo.amount)
                .tabularAmount()
                .foregroundColor(DS.Ink.primary)
        }
        .padding(.vertical, DS.Spacing.medium)
        .accessibilityElement(children: .combine)
    }

    /// 이름을 적는 건 **셋까지**다. 넷째부터는 "그 외 N개" 한 줄로 합친다 —
    /// 카테고리가 열 개인 달에 열 줄을 세우면 1등이 안 보인다.
    private var rows: [CategoryTotal] {
        let named = Array(totals.prefix(DS.Palette.categorySeries.count))
        let rest = totals.dropFirst(DS.Palette.categorySeries.count)
        guard !rest.isEmpty else { return named }
        return named + [CategoryTotal(name: "그 외 \(rest.count)개",
                                      amount: rest.reduce(0) { $0 + $1.amount })]
    }

    /// 사다리 밖(그 외)은 뜻 없는 회색이다.
    private func color(at index: Int) -> Color {
        index < DS.Palette.categorySeries.count
            ? DS.Palette.categorySeries[index]
            : DS.Palette.categoryRest
    }
}
