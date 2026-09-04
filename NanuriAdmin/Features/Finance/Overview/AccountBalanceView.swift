import SwiftUI

/// 통장별 잔액과 총 재정을 보는 화면. 재정 탭 헤더 왼쪽의 통장 버튼이 연다.
///
/// ```
/// 닫기 ✕                        ← 오른쪽 위. 다른 시트와 같은 자리다
/// 9,128,884원                   ← 총 재정. 큰 수 하나가 홀로 선다
/// 지금 통장에 있는 돈을 모두 합한 금액이에요
/// ────────────────
/// 농협                5,783,084원
/// 모임                3,345,800원
/// ────────────────
/// 2026년 8월에 통장 사이에서 오간 돈
/// 농협 → 모임          4,000,000원
/// 장부 전체로 보면 나간 돈도 들어온 돈도 아니라, 총 입금·총 출금과 보고서에는
/// 들어가지 않아요
/// ```
///
/// **잔액을 저장하지 않기 때문에 이 화면이 필요하다.** `finance_transactions.balance`
/// 를 없앤 뒤로 앱 어디에도 "지금 얼마 있나" 를 말하는 자리가 없었다. 잔액은
/// `finance_accounts.opening_balance` 에서 누적해 유도하고(`FinanceViewModel.balance(of:)`),
/// 그 값을 읽는 곳은 여기 하나다.
///
/// **요약 밴드에 넣지 않았다.** 밴드가 내놓는 수는 총 입금·총 출금 둘뿐이고, 셋이
/// 되는 순간 어느 것을 봐야 하는지 흐려진다 (DESIGN.md 12번). 그리고 밴드의 두 수는
/// **이 달에 오간 돈**인데 잔액은 **쌓인 돈**이라, 나란히 두면 같은 종류의 수처럼
/// 읽힌다.
///
/// **보고 있는 달의 끝을 기준으로 센다.** 이번 달이면 아직 오지 않은 끝이라 곧 지금
/// 잔액이고, 지난달을 펼쳐 두고 열면 그 달이 끝났을 때의 잔액이다. 화면이 3월을
/// 보고 있는데 여기만 오늘을 말하면 두 화면이 다른 시점을 말하게 된다.
/// 이 성질이 곧 **검산**이기도 하다 — 모임통장은 월말 결산에서 잔액을 농협으로
/// 돌려보내므로 지난달 끝에서 0 으로 떨어져 있어야 한다.
///
/// 여기서 달을 넘기지 않는다. 분석 화면과 같은 이유로, **어느 한 달을 들고 들어오는**
/// 화면이라 여기서 달이 바뀌면 뒤에 남겨 둔 목록과 어긋난다.
struct AccountBalanceView: View {
    @ObservedObject var viewModel: FinanceViewModel

    @Environment(\.dismiss) private var dismiss

    /// 잔액을 세는 시점. 보고 있는 달의 마지막 순간이다.
    private var asOf: Date { viewModel.endDate }

    /// 이번 달을 보고 있나. 기준을 말하는 문장이 갈린다.
    private var isThisMonth: Bool {
        Calendar.current.startOfMonth(Date()) == viewModel.currentMonth
    }

    var body: some View {
        VStack(spacing: 0) {
            closeBar

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    if viewModel.accounts.isEmpty {
                        EmptyStateView(
                            title: "통장이 아직 없어요",
                            message: "장부에 통장이 등록돼야 잔액을 셀 수 있어요"
                        ) { EmptyView() }
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Spacing.s12)
                    } else {
                        headline
                        Divider()
                        accountList
                        if !flows.isEmpty {
                            Divider()
                            transferSection
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.sheetEdge)
            }
        }
        .presentationDetents([.large])
        .screenBackground(DS.Surface.card)
    }

    /// 오른쪽 위 ✕. 청구서 상세·분석 화면과 같은 자리다.
    private var closeBar: some View {
        HStack {
            Spacer()
            HeaderIconButton(systemName: "xmark", label: "닫기") { dismiss() }
        }
        .padding(.horizontal, DS.Spacing.small)
    }

    // MARK: - 머리

    /// 총 재정 한 수와, 그 수가 언제 기준인지 말하는 문장.
    ///
    /// **수가 먼저고 문장이 아래다.** 큰 수 하나가 홀로 서는 자리는 요약 밴드의
    /// 두 칸과 반대 순서다 (DESIGN.md 12번).
    private var headline: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text("\(viewModel.totalBalance(asOf: asOf).formatted())원")
                .typeStyle(DS.Typo.h1)
                .tabularAmount()
                .foregroundColor(DS.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(isThisMonth
                 ? "지금 통장에 있는 돈을 모두 합한 금액이에요"
                 : "\(viewModel.currentMonth.koreanYearMonthString)이 끝났을 때 금액이에요")
                .typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Spacing.medium)
    }

    // MARK: - 통장별

    /// 통장 한 줄에 수 하나. 개시잔액도 이 달 입출금도 여기 적지 않는다 —
    /// 이 화면이 답하는 질문은 "지금 얼마 있나" 하나뿐이다.
    private var accountList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.accounts) { account in
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let balance = viewModel.balance(of: account, asOf: asOf)
        return HStack(spacing: DS.Spacing.medium) {
            Text(account.name)
                .rowTitle()
                .lineLimit(1)

            Spacer(minLength: DS.Spacing.small)

            // 마이너스는 통장에서 일어나면 안 되는 일이라 위험색을 준다.
            // 출금이 검정인 것과 다르다 — 저건 일상이고 이건 어긋난 것이다.
            Text("\(balance.formatted())원")
                .typeStyle(DS.Typo.amount)
                .tabularAmount()
                .foregroundColor(balance < 0 ? DS.Palette.danger : DS.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, DS.Spacing.medium)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 통장 사이에서 오간 돈

    private var flows: [AccountFlow] { viewModel.internalTransferFlows }

    /// 이 달의 내부 이체를 방향별로 합쳐 보여준다.
    ///
    /// **여기 있는 이유는 두 수가 어긋나 보이기 때문이다.** 예산 400만원을 농협에서
    /// 모임으로 옮긴 달은 통장 잔액이 크게 움직이는데 요약 밴드의 총 출금은 꿈쩍도
    /// 안 한다(합계에서 빼기 때문에). 그 차이를 설명하는 자리가 없으면 둘 중 하나가
    /// 틀린 것처럼 보인다.
    private var transferSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text("\(viewModel.currentMonth.koreanYearMonthString)에 통장 사이에서 오간 돈")
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.secondary)

            VStack(spacing: 0) {
                ForEach(flows) { flow in
                    flowRow(flow)
                }
            }

            Text("장부 전체로 보면 나간 돈도 들어온 돈도 아니라, 총 입금·총 출금과 보고서에는 들어가지 않아요")
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func flowRow(_ flow: AccountFlow) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            HStack(spacing: DS.Spacing.tight) {
                Text(name(of: flow.direction.from))
                Image(systemName: "arrow.right")
                    .font(DS.Icon.font(DS.Icon.s))
                    .foregroundColor(DS.Ink.tertiary)
                Text(name(of: flow.direction.to))
            }
            .rowTitle()
            .lineLimit(1)

            Spacer(minLength: DS.Spacing.small)

            Text("\(flow.amount.formatted())원")
                .typeStyle(DS.Typo.amount)
                .tabularAmount()
                .foregroundColor(DS.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, DS.Spacing.medium)
        .accessibilityElement(children: .combine)
        // 조사가 이름을 타지 않게 **고정된 낱말("통장")에 붙인다.** 받침 유무로
        // "으로/로" 를 가르는 규칙을 이 한 줄 때문에 들여올 이유가 없다.
        .accessibilityLabel("\(name(of: flow.direction.from)) 통장에서 \(name(of: flow.direction.to)) 통장으로 옮긴 돈 \(flow.amount.formatted())원")
    }

    /// 통장 이름. 지워진 통장을 가리키는 거래가 남아 있을 수 있어 대비를 둔다.
    private func name(of id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }
}
