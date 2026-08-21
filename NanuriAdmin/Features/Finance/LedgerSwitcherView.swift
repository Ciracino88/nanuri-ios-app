import SwiftUI

/// 지금 보는 장부를 바꾸는 시트. 헤더 가운데 "재정 ▾" 를 누르면 열린다.
///
/// **고르는 건 장부(통장)지 유형이 아니다.** 월별 회계 · 행사 결산은 장부에 붙은
/// 성질이라 행의 두 번째 줄에 적는다. 통장이 늘면 목록이 늘어난다.
///
/// 구조는 계정 전환기와 같다 — 상자 하나에 고를 것들을 쌓고 **지금 것에 체크**,
/// 맨 아래 줄이 "새로 만들기", 상자 밖에 관리로 나가는 버튼. 되돌아가는 화면이
/// 아니라 **고르는 자리**라는 게 열자마자 보이는 게 이 구조의 값어치다.
/// (예전에는 제목을 누르면 장부 게이트 화면으로 되돌아갔는데, ▾ 는 펼쳐진다는
/// 뜻이지 뒤로 간다는 뜻이 아니라서 눌러 봐야 알 수 있었다.)
///
/// **시트가 직접 다음 시트를 열지 않는다.** 새 장부 만들기는 이 시트가 닫힌 뒤
/// `FinanceView` 가 연다 — 시트 위에 시트를 겹치면 SwiftUI 가 뒤엣것을 조용히
/// 삼킨다 (`BillListView` 와 같은 사정).
struct LedgerSwitcherView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let onSelect: (Ledger) -> Void
    let onCreate: () -> Void
    let onManage: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.section) {
                VStack(spacing: 0) {
                    ForEach(viewModel.ledgers) { ledger in
                        Button { onSelect(ledger) } label: { row(ledger) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                    Button(action: onCreate) { createRow }
                        .buttonStyle(.plain)
                }
                // 상자 안쪽 여백은 행이 갖는다. 행 전체가 눌리는 면이라
                // 상자가 여백을 가지면 그 테두리 안쪽이 안 눌린다.
                .groupBox(padding: 0)

                // 지우고 만드는 건 게이트 화면 몫이다. 여기서는 고르기만 한다.
                ActionButton(title: "장부 관리", action: onManage)
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.sheetEdge)
        }
        // 장부 수가 사람마다 다르니 **재서 맞추지 않는다** (`TROUBLESHOOTING.md`).
        // 남으면 아래가 비고 모자라면 스크롤된다.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // 다른 기기에서 장부를 만들었을 수도 있다. 열 때마다 다시 받는다.
        .task { await viewModel.fetchLedgers() }
    }

    private func row(_ ledger: Ledger) -> some View {
        let isCurrent = ledger.id == viewModel.currentLedger?.id
        return HStack(spacing: DS.Spacing.medium) {
            icon(ledger.mode.icon, tone: DS.Tone.brand)
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(ledger.name)
                    .sheetTitle()
                Text(ledger.mode.title)
                    .sheetSubtext()
            }
            Spacer(minLength: DS.Spacing.small)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(DS.Icon.font(DS.Icon.l))
                    .foregroundColor(DS.Palette.accent)
            }
        }
        .padding(DS.Spacing.screen)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ledger.name), \(ledger.mode.title)\(isCurrent ? ", 지금 보는 장부" : "")")
    }

    /// 맨 아래 줄. 고르는 것들과 같은 상자에 있지만 **파랑을 주지 않는다** —
    /// 여기서 하려던 일은 고르기고, 만들기는 그 다음이다.
    private var createRow: some View {
        HStack(spacing: DS.Spacing.medium) {
            icon("plus", tone: DS.Tone.neutral)
            Text("새 장부 만들기")
                .sheetTitle()
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.screen)
        .contentShape(Rectangle())
    }

    /// 게이트 화면(`FinanceLedgerGateView`) 행과 같은 모양이다. 같은 장부를
    /// 두 화면이 다르게 그리면 옮겨 다닐 때 다른 것으로 보인다.
    private func icon(_ systemName: String, tone: DS.ColorTone) -> some View {
        Image(systemName: systemName)
            .font(DS.Icon.font(DS.Icon.l))
            .foregroundColor(tone.content)
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
            .background(tone.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
    }
}
