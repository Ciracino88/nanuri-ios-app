import SwiftUI

/// 거래 추가에서 날짜를 고르는 **가로 주 단위 셀렉터.**
///
/// 재정 탭의 `FinanceDaySelector` 와 같은 시각 문법이다 — 한 화면에 한 주씩,
/// 옆으로 넘기면 주 단위로 딱딱 끊긴다. 다만 그쪽은 순증감을 보여주고 목록을
/// 거르는 도구라, 여기서는 그 부분을 걷고 **날짜 하나를 고르는** 일만 남겼다.
///
/// 보이는 범위는 지금 보고 있는 달(`weeksInCurrentMonth`)이다. 그 달에 거래를
/// 넣는 화면이라 그걸로 충분하다 — 다른 달은 목록에서 달을 넘긴 뒤 연다.
struct WeekDatePicker: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var selection: Date

    private let cal = Calendar.current

    var body: some View {
        let weeks = viewModel.weeksInCurrentMonth
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in dayCell(day) }
                        }
                        .padding(.horizontal, DS.Spacing.medium)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .padding(.top, DS.Spacing.small)
            .padding(.bottom, DS.Spacing.medium)
            .onAppear {
                guard let week = weeks.firstIndex(where: {
                    $0.contains { cal.isDate($0, inSameDayAs: selection) }
                }) else { return }
                proxy.scrollTo(week, anchor: .center)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isThisMonth = viewModel.isInCurrentMonth(day)
        let isSelected = cal.isDate(day, inSameDayAs: selection)
        return Button {
            withAnimation(DS.Motion.control) {
                // 고른 날 + 지금 시각. 같은 날 여러 건을 넣어도 넣은 순서를 지킨다.
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                let now = cal.dateComponents([.hour, .minute, .second], from: Date())
                comps.hour = now.hour; comps.minute = now.minute; comps.second = now.second
                selection = cal.date(from: comps) ?? day
            }
        } label: {
            VStack(spacing: DS.Spacing.s1 / 2) {
                Text(day.koreanWeekdayString)
                    .typeStyle(DS.Typo.captionS)
                    .foregroundColor(DS.Ink.placeholder)
                Text(day.koreanDayNumberString)
                    .typeStyle(DS.Typo.labelM)
                    .tabularAmount()
                    .foregroundColor(isSelected ? DS.Ink.inverse : DS.Ink.primary)
                    .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                    .background(isSelected ? DS.Ink.primary : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isThisMonth)
        .opacity(isThisMonth ? 1 : DS.State.disabledOpacity)
        .accessibilityLabel(day.koreanDaySectionString)
    }
}
