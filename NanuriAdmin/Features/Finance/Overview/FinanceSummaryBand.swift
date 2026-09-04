import SwiftUI

struct FinanceSummaryBand: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var showSpendingDetail: Bool

    /// 요약 밴드.
    ///
    /// **카드가 아니다** — 라운드도 좌우 여백도 없이 화면 폭을 가로지르는 띠다.
    /// 목록이 흰 바탕이라 이 띠 하나가 회색으로 서면서 화면 위쪽을 잡아 준다.
    ///
    /// 내놓는 수는 **둘뿐이다** — 총 입금과 총 출금. 한때 잔액까지 셋을 세웠는데,
    /// 셋이 되는 순간 어느 것을 봐야 하는지가 흐려진다. 월 수지는 이 둘의 차라
    /// 눈으로 읽을 수 있고, 통장 잔액은 헤더 왼쪽의 통장 화면(`AccountBalanceView`)
    /// 에 있다 — 여기 두 수가 **이 달에 오간 돈**인 데 반해 잔액은 **쌓인 돈**이라
    /// 나란히 서면 같은 종류의 수로 읽힌다.
    ///
    /// **라벨이 위, 숫자가 아래다.** 여기서는 "무엇의 수인지"를 먼저 알아야
    /// 수가 읽힌다.
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DS.Spacing.s4) {
                bandAmount(label: "총 입금",
                           text: "+\(viewModel.totalDeposit.formatted())원",
                           color: DS.Palette.deposit)
                bandAmount(label: "총 출금",
                           text: "-\(viewModel.totalWithdrawal.formatted())원",
                           color: DS.Palette.withdrawal)
            }
            .padding(.horizontal, DS.Spacing.s4)
            .padding(.top, DS.Spacing.s6)
            .padding(.bottom, DS.Spacing.s5)

            Rectangle()
                .fill(DS.Line.default)
                .frame(height: DS.Line.hairline)
                .padding(.horizontal, DS.Spacing.s4)

            insightRow()
        }
        .background(DS.Surface.secondary)
    }

    /// 밴드 위쪽 두 칸. **라벨이 위, 수가 아래**다.
    private func bandAmount(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
            Text(label)
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.secondary)
            Text(text)
                .typeStyle(DS.Typo.h4)
                .tabularAmount()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 밴드 발치 줄 — 왼쪽은 지난달과 견준 한 문장과 "자세히 보기", 오른쪽은 그래프.
    ///
    /// 문장은 **결과**를 말하고 그래프는 **언제 벌어졌는지**를 말한다. 둘이 같은
    /// 자리에 있어야 "왜 그런지" 까지 한눈에 읽힌다.
    ///
    /// 장부를 고르는 자리가 잠깐 여기 있었는데, 그 자리를 "자세히 보기" 에 내줬다.
    /// (장부 고르기는 그 뒤 헤더로 갔다가, 통장이 하나라 아예 없어졌다.)
    private func insightRow() -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.medium) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                // 본문보다 한 계층 작다. 대신 **금액만** 굵기와 색으로 도드라져서
                // 문장을 다 읽지 않아도 수가 먼저 눈에 걸린다.
                viewModel.comparison.text
                    .typeStyle(DS.Typo.labelS)
                    .foregroundColor(DS.Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // 보고서(종이)가 아니라 **분석 화면**이 열린다. 밴드는 소비 이야기를
                // 하고 있는데 종이 장부를 열면 문맥이 끊기고, 보고서로 가는 길은
                // 헤더 메뉴에 따로 있다 (`actionMenu`).
                Button {
                    showSpendingDetail = true
                } label: {
                    HStack(spacing: DS.Spacing.tight) {
                        Text("자세히 보기")
                            .typeStyle(DS.Typo.body3)
                        Image(systemName: "chevron.right")
                            .font(DS.Icon.font(DS.Icon.s))
                    }
                    .foregroundColor(DS.Ink.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.filtered.isEmpty)
            }

            Spacer(minLength: DS.Spacing.small)

            // 견줄 지난달이 없으면 선이 하나뿐이라 "견주는 그래프" 가 아니게 된다.
            // 그럴 땐 아예 안 그린다.
            if viewModel.comparison.hasPrevious {
                SpendingSparkline(
                    current: viewModel.cumulativeWithdrawals(monthsAgo: 0),
                    previous: viewModel.cumulativeWithdrawals(monthsAgo: 1),
                    tint: viewModel.comparison.color
                )
            }
        }
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.s4)
    }
}
