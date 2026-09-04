import SwiftUI

struct FinanceDaySelector: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var selectedDay: Date?

    /// 날짜 셀렉터.
    ///
    /// **한 화면에 한 주씩 놓이고, 옆으로 넘기면 주 단위로 딱딱 끊긴다.**
    /// 날짜를 이어 붙여 자유롭게 흐르게 두면 요일 자리가 매번 달라져서, 늘 같은
    /// 칸에 있어야 할 "토요일" 을 눈으로 못 찾는다.
    ///
    /// 누르면 그날만 걸러 본다. **한 번 더 누르면 풀린다** — 되돌아갈 길을 따로
    /// 만들지 않으려고 같은 자리를 토글로 쓴다.
    var body: some View {
        let net = viewModel.dailyNet
        let weeks = viewModel.weeksInCurrentMonth
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                dayCell(day, net: net[day])
                            }
                        }
                        .padding(.horizontal, DS.Spacing.medium)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .padding(.top, DS.Spacing.s5)
            .padding(.bottom, DS.Spacing.s6)
            .onAppear {
                // 자료가 있는 마지막 날이 든 주를 펼쳐 둔다. 달을 열면 보통
                // 최근 것부터 확인한다.
                guard let last = net.keys.max(),
                      let week = weeks.firstIndex(where: { $0.contains(last) }) else { return }
                proxy.scrollTo(week, anchor: .center)
            }
        }
    }

    /// 하루 칸. 일곱이 화면 폭을 고르게 나눠 갖는다.
    ///
    /// 주 단위로 끊다 보면 앞뒤 달 날짜가 섞이는데, **그 칸은 흐리게 두고 누를 수
    /// 없다** — 이 화면이 가진 자료가 이 달치뿐이라 눌러 봐야 빈 목록만 나온다.
    private func dayCell(_ day: Date, net: Int?) -> some View {
        let isThisMonth = viewModel.isInCurrentMonth(day)
        let isSelected = selectedDay == day
        return Button {
            withAnimation(DS.Motion.control) {
                selectedDay = isSelected ? nil : day
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
                // 칸이 좁아서 만 단위로 줄인다 (`89.3만`). 온전한 수를 넣으면
                // 글자가 절반 크기까지 줄어들어 결국 안 읽힌다. 정확한 수는
                // 그 날을 눌러 목록에서 본다.
                Text(net.map(dayNetLabel) ?? " ")
                    .typeStyle(DS.Typo.captionS)
                    .tabularAmount()
                    .foregroundColor(netColor(net))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isThisMonth)
        .opacity(isThisMonth ? 1 : DS.State.disabledOpacity)
        .accessibilityLabel("\(day.koreanDaySectionString)\(isSelected ? ", 고름" : "")")
    }

    /// 그날 순증감 라벨. **0 은 부호를 붙이지 않는다** — 같은 날 입출금이
    /// 상쇄되면 실제로 0 이 나오는데, 거기에 `-` 를 붙이면 `-0` 이 된다.
    private func dayNetLabel(_ net: Int) -> String {
        if net == 0 { return "0" }
        return "\(net > 0 ? "+" : "-")\(abs(net).compactAmount)"
    }

    private func netColor(_ net: Int?) -> Color {
        guard let net, net != 0 else { return DS.Ink.placeholder }
        return net > 0 ? DS.Palette.deposit : DS.Ink.secondary
    }
}
