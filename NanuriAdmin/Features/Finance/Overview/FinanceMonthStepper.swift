import SwiftUI

struct FinanceMonthStepper: View {
    @ObservedObject var viewModel: FinanceViewModel

    /// 헤더 가운데에 들어가는 달 넘김.
    ///
    /// 화살표를 글자 양옆에 바짝 붙인다 — 헤더 폭이 좁아서 예전처럼 화면 양 끝으로
    /// 벌리면 가운데가 비어 보인다. 달 이름을 누르면 목록에서 바로 건너뛴다
    /// (20개월을 한 칸씩 넘기지 않아도 되게).
    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            monthStep(systemName: "chevron.left",
                      label: "이전 달",
                      enabled: viewModel.canGoToPreviousMonth) {
                viewModel.goToPreviousMonth()
            }

            Menu {
                ForEach(viewModel.selectableMonths.reversed(), id: \.self) { month in
                    Button {
                        viewModel.currentMonth = month
                    } label: {
                        if viewModel.hasTransactions(in: month) {
                            Text(month.koreanYearMonthString)
                        } else {
                            Label(month.koreanYearMonthString, systemImage: "minus.circle")
                        }
                    }
                }
            } label: {
                Text(viewModel.currentMonth.koreanYearMonthString)
                    .typeStyle(DS.Typo.title1)
                    .foregroundColor(DS.Ink.primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("달 고르기")

            monthStep(systemName: "chevron.right",
                      label: "다음 달",
                      enabled: viewModel.canGoToNextMonth) {
                viewModel.goToNextMonth()
            }
        }
        .animation(DS.Motion.control, value: viewModel.currentMonth)
    }

    private func monthStep(systemName: String, label: String,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DS.Icon.font(DS.Icon.inline))
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .foregroundColor(DS.Ink.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // 비활성은 부분 회색 처리 없이 노드 전체에 건다.
        .opacity(enabled ? 1 : DS.State.disabledOpacity)
        .accessibilityLabel(label)
    }
}
