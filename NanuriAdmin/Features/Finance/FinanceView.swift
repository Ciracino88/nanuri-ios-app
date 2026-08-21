import SwiftUI

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab = 0
    @State private var editingTransaction: BankTransaction?
    @State private var showStatements = false
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    @State private var exportMessage = "내보내는 중…"
    @State private var reportPreview: ReportPreview?
    /// 헤더 가운데를 눌러 여는 장부 전환 시트.
    @State private var showSwitcher = false
    /// 전환 시트가 닫힌 **뒤에** 할 일. 시트 위에 시트를 겹치지 않으려고 한 박자 미룬다.
    @State private var afterSwitcher: (() -> Void)?
    @State private var showNewLedger = false
    /// 날짜 셀렉터에서 고른 날. `nil` 이면 이 달 전체다.
    @State private var selectedDay: Date?

    var body: some View {
        if let ledger = viewModel.currentLedger {
            content(ledger: ledger)
        } else {
            FinanceLedgerGateView(viewModel: viewModel)
        }
    }

    private func content(ledger: Ledger) -> some View {
        let mode = ledger.mode
        return VStack(spacing: 0) {
            // 가운데를 **달 넘김**에 내줬다. 탭 이름("재정")은 탭바가 이미 말하고
            // 있고, 이 화면에서 가장 자주 건드리는 건 달이다.
            //
            // 장부를 고르는 길은 **왼쪽 슬롯**이 갖는다. 요약 밴드에 잠깐 뒀다가
            // 그 자리가 "자세히 보기" 로 넘어가면서 헤더로 돌아왔다.
            Group {
                if mode == .monthly {
                    AdminHeaderView(
                        center: { monthStepper },
                        leading: { ledgerButton(ledger) },
                        trailing: { actionMenu(mode: mode) }
                    )
                } else {
                    AdminHeaderView(
                        title: "재정",
                        titleAction: { showSwitcher = true },
                        trailing: { actionMenu(mode: mode) }
                    )
                }
            }

            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.transactions.isEmpty {
                    emptyView
                } else {
                    scrollingContent(ledger: ledger, mode: mode)
                }
            }
            .overlay {
                if isExporting {
                    ZStack {
                        DS.State.scrim.ignoresSafeArea()
                        VStack(spacing: DS.Spacing.medium) {
                            ProgressView()
                            Text(exportMessage)
                                .typeStyle(DS.Typo.body2)
                                .foregroundColor(DS.Ink.secondary)
                        }
                        .padding(DS.Spacing.screen)
                        .background(DS.Surface.card)
                        // 떠 있는 판이라 여기서는 그림자를 쓴다.
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl2))
                        .elevation(.dialog)
                    }
                }
            }
            .alert("오류", isPresented: .constant(viewModel.error != nil)) {
                Button("확인") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(item: $editingTransaction) { tx in
                TransactionEditView(transaction: tx, suggestions: viewModel.usedCategories, viewModel: viewModel)
            }
            .sheet(isPresented: $showStatements) {
                StatementsListView(viewModel: viewModel)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .sheet(item: $reportPreview) { preview in
                FinanceReportPreviewView(html: preview.html, title: preview.title)
            }
            // 전환 시트가 완전히 닫힌 뒤에 다음 일을 한다. 같은 순간에 둘을
            // 겹치면 SwiftUI 가 뒤엣것을 조용히 삼킨다 (`BillListView` 와 같다).
            .sheet(isPresented: $showSwitcher, onDismiss: {
                afterSwitcher?()
                afterSwitcher = nil
            }) {
                LedgerSwitcherView(
                    viewModel: viewModel,
                    onSelect: { picked in
                        // 보고 있던 장부를 다시 고르면 아무 일도 안 한다.
                        // 다시 받아 오면 달 위치까지 처음으로 되돌아간다.
                        if picked.id != viewModel.currentLedger?.id {
                            afterSwitcher = { Task { await viewModel.selectLedger(picked) } }
                        }
                        showSwitcher = false
                    },
                    onCreate: {
                        afterSwitcher = { showNewLedger = true }
                        showSwitcher = false
                    },
                    onManage: {
                        // 장부를 비우면 게이트 화면이 나온다 — 거기서 만들고 지운다.
                        afterSwitcher = { viewModel.currentLedger = nil }
                        showSwitcher = false
                    }
                )
            }
            .sheet(isPresented: $showNewLedger) {
                NewLedgerView(viewModel: viewModel)
            }
        }
        // 목록이 흰 바탕에 그냥 앉는 구조라 페이지가 흰색이다. 회색으로 서는 건
        // 요약 밴드 하나뿐이고, 그 대비가 화면 위쪽을 잡아 준다.
        .screenBackground(DS.Surface.card)
        .task {
            await viewModel.fetchTransactions()
            viewModel.loadSavedStatements()
        }
    }

    /// 헤더 가운데에 들어가는 달 넘김.
    ///
    /// 화살표를 글자 양옆에 바짝 붙인다 — 헤더 폭이 좁아서 예전처럼 화면 양 끝으로
    /// 벌리면 가운데가 비어 보인다. 달 이름을 누르면 목록에서 바로 건너뛴다
    /// (20개월을 한 칸씩 넘기지 않아도 되게).
    private var monthStepper: some View {
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

    /// 요약 밴드.
    ///
    /// **카드가 아니다** — 라운드도 좌우 여백도 없이 화면 폭을 가로지르는 띠다.
    /// 목록이 흰 바탕이라 이 띠 하나가 회색으로 서면서 화면 위쪽을 잡아 준다.
    ///
    /// 내놓는 수는 **둘뿐이다** — 총 입금과 총 출금. 한때 잔액까지 셋을 세웠는데,
    /// 셋이 되는 순간 어느 것을 봐야 하는지가 흐려진다. 월 수지는 이 둘의 차라
    /// 눈으로 읽을 수 있고, 통장의 실제 잔액은 거래 상세의 "거래 후 잔액" 에 있다.
    ///
    /// **라벨이 위, 숫자가 아래다.** 여기서는 "무엇의 수인지"를 먼저 알아야
    /// 수가 읽힌다.
    private func summaryBand(ledger: Ledger) -> some View {
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

            insightRow(ledger: ledger)
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

    /// 밴드 발치 줄 — 왼쪽은 지난달과 견준 한 문장과 장부 바꾸기, 오른쪽은 그래프.
    ///
    /// 문장은 **결과**를 말하고 그래프는 **언제 벌어졌는지**를 말한다. 둘이 같은
    /// 자리에 있어야 "왜 그런지" 까지 한눈에 읽힌다.
    ///
    /// 장부 이름이 헤더에서 빠졌으므로 **여기가 장부를 고르는 자리**다.
    /// 화면이 어느 장부인지는 어디선가 반드시 말해야 한다.
    private func insightRow(ledger: Ledger) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.medium) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                // 본문보다 한 계층 작다. 대신 **금액만** 굵기와 색으로 도드라져서
                // 문장을 다 읽지 않아도 수가 먼저 눈에 걸린다.
                comparisonText
                    .typeStyle(DS.Typo.labelS)
                    .foregroundColor(DS.Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    // 지금은 이 달 보고서를 연다. 전용 분석 화면이 생기면 그쪽으로 바꾼다.
                    if let html = viewModel.reportHTML() {
                        reportPreview = ReportPreview(html: html, title: ledger.mode.title)
                    }
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
            if viewModel.previousMonthWithdrawal != nil {
                SpendingSparkline(
                    current: viewModel.cumulativeWithdrawals(monthsAgo: 0),
                    previous: viewModel.cumulativeWithdrawals(monthsAgo: 1),
                    tint: comparisonColor
                )
            }
        }
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.s4)
    }

    /// 지난달과 견준 한 문장. 견줄 지난달이 없으면 이 달 수지를 대신 말한다.
    ///
    /// **금액 조각만 굵기와 색을 달리 준다.** 문장 전체를 강조하면 밴드에서
    /// 제일 무거운 덩어리가 되는데, 그 자리는 위의 두 수 것이다.
    private var comparisonText: Text {
        guard let previous = viewModel.previousMonthWithdrawal else {
            let net = viewModel.totalDeposit - viewModel.totalWithdrawal
            return net < 0
                ? amountPart(abbreviated(-net)) + Text(" 더 나갔어요")
                : amountPart(abbreviated(net)) + Text(" 남았어요")
        }
        let diff = viewModel.totalWithdrawal - previous
        if diff == 0 { return Text("지난달과 똑같이 썼어요") }
        return Text("지난달보다 ")
            + amountPart(abbreviated(abs(diff)))
            + Text(diff > 0 ? " 더 썼어요" : " 덜 썼어요")
    }

    private func amountPart(_ text: String) -> Text {
        Text(text).fontWeight(.bold).foregroundColor(comparisonColor)
    }

    /// **더 썼으면 빨강, 덜 썼으면 파랑.** 그래프의 이 달 선도 같은 색을 쓴다 —
    /// 문장과 그림이 같은 것을 말하고 있다는 걸 색이 묶어 준다.
    ///
    /// 이 앱에서 빨강은 되돌릴 수 없는 것의 색이라 아껴 왔는데, 여기서는 예외로
    /// 둔다. 지출이 늘어난 건 되돌릴 수 없는 일이 맞고, 견주는 자리라 색이
    /// 없으면 문장이 그냥 흘러간다.
    private var comparisonColor: Color {
        guard let previous = viewModel.previousMonthWithdrawal else { return DS.Ink.brand }
        return viewModel.totalWithdrawal > previous ? DS.Palette.danger : DS.Palette.deposit
    }

    /// 헤더 왼쪽의 장부 전환. 아이콘 하나라 이름은 VoiceOver 가 읽는다.
    private func ledgerButton(_ ledger: Ledger) -> some View {
        HeaderIconButton(systemName: ledger.mode.icon,
                         label: "장부 바꾸기, 지금 \(ledger.name)") {
            showSwitcher = true
        }
    }

    /// 문장 안에 들어가는 금액은 만 단위로 줄인다 — 문장은 정확한 수를 읽는
    /// 자리가 아니라 크기를 가늠하는 자리다. 정확한 수는 바로 위 두 칸에 있다.
    private func abbreviated(_ amount: Int) -> String {
        amount >= 10_000
            ? "\((amount / 10_000).formatted())만원"
            : "\(amount.formatted())원"
    }

    /// 날짜 셀렉터.
    ///
    /// **한 화면에 한 주씩 놓이고, 옆으로 넘기면 주 단위로 딱딱 끊긴다.**
    /// 날짜를 이어 붙여 자유롭게 흐르게 두면 요일 자리가 매번 달라져서, 늘 같은
    /// 칸에 있어야 할 "토요일" 을 눈으로 못 찾는다.
    ///
    /// 누르면 그날만 걸러 본다. **한 번 더 누르면 풀린다** — 되돌아갈 길을 따로
    /// 만들지 않으려고 같은 자리를 토글로 쓴다.
    private var daySelector: some View {
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

    private var currentItems: [BankTransaction] {
        let byKind: [BankTransaction]
        switch selectedTab {
        case 1: byKind = viewModel.deposits
        case 2: byKind = viewModel.withdrawals
        default: byKind = viewModel.filtered
        }
        guard let selectedDay else { return byKind }
        let cal = Calendar.current
        return byKind.filter { cal.startOfDay(for: $0.datetime) == selectedDay }
    }

    /// 같은 날 거래를 한 덩어리로 묶는다. 목록 순서를 그대로 따라가므로
    /// 뷰모델이 정렬을 바꾸면 여기도 자연히 따라간다.
    private var dayGroups: [DayGroup] {
        var groups: [DayGroup] = []
        let calendar = Calendar.current
        for tx in currentItems {
            let day = calendar.startOfDay(for: tx.datetime)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(tx)
            } else {
                groups.append(DayGroup(day: day, items: [tx]))
            }
        }
        return groups
    }

    /// **화면 전체가 한 덩어리로 스크롤된다.**
    ///
    /// 예전에는 달 줄·요약 카드·세그먼트가 위에 붙박이고 목록만 스크롤됐다.
    /// 화면 절반이 고정이라 목록이 좁은 창으로 보였고, 훑을 때 답답했다.
    /// 고정으로 남는 건 헤더뿐이다.
    ///
    /// `List` 가 아니라 `ScrollView` 다 — 목록에 스와이프 동작이 없어서 `List` 를
    /// 쓸 이유가 없고, 머리 콘텐츠를 같이 굴리려면 이쪽이 맞다.
    private func scrollingContent(ledger: Ledger, mode: FinanceReportMode) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 레퍼런스 순서 그대로 — 거르개가 먼저, 요약이 그다음, 날짜 축이
                // 그 아래, 목록이 맨 끝이다. 위에서 아래로 범위가 좁혀진다.
                ChipSelector(items: [
                    .init(value: 0, label: "전체", count: viewModel.filtered.count),
                    .init(value: 1, label: "입금", count: viewModel.deposits.count),
                    .init(value: 2, label: "출금", count: viewModel.withdrawals.count)
                ], selection: $selectedTab)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.s5)

                summaryBand(ledger: ledger)

                if mode == .monthly {
                    daySelector
                }

                if currentItems.isEmpty {
                    // 장부 전체가 아니라 **지금 걸러 놓은 범위만** 비어 있는 경우다.
                    // 전체 빈 화면으로 덮으면 달 넘김·날짜 축까지 사라져서
                    // 빠져나갈 길이 없어진다.
                    EmptyStateView(
                        title: emptyRangeTitle,
                        message: emptyRangeMessage
                    )
                    .padding(.top, DS.Spacing.s12)
                } else {
                    ForEach(dayGroups) { group in
                        daySection(group)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.s8)
            .animation(DS.Motion.list, value: selectedTab)
            .animation(DS.Motion.list, value: viewModel.currentMonth)
            .animation(DS.Motion.list, value: selectedDay)
            // 달을 넘기면 고른 날은 이 달에 없는 날이 된다. 같이 푼다.
            .onChange(of: viewModel.currentMonth) { _, _ in selectedDay = nil }
        }
        .scrollBounceBehavior(.always)
        .refreshable { await reload() }
    }

    /// 하루치 섹션.
    ///
    /// **카드가 아니다.** 날짜가 회색 글씨로 앉고 그 아래 거래들이 흰 바탕 위에
    /// 바로 놓인다 — 구분선도 상자도 없이 여백만으로 갈린다.
    ///
    /// 하루당 카드 한 장이던 적이 있는데, 카드 테두리가 날짜마다 생기니 화면이
    /// 다시 상자의 반복이 됐다. 훑는 화면에서 상자는 리듬을 끊는다.
    private func daySection(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.day.koreanDaySectionString)
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.secondary)
                .padding(.horizontal, DS.Spacing.s4)
                .padding(.top, DS.Spacing.s6)
                .padding(.bottom, DS.Spacing.medium)

            ForEach(group.items) { tx in
                TransactionRowView(transaction: tx, splits: viewModel.splits(for: tx.id))
                    .contentShape(Rectangle())
                    .onTapGesture { editingTransaction = tx }
            }
        }
    }

    /// 비어 있는 이유가 셋이라 문구도 셋이다 — 고른 날이 비었나, 거르개가
    /// 비었나, 이 달이 통째로 비었나. "다른 달을 보세요" 를 날짜 필터가 켜진
    /// 채로 띄우면 엉뚱한 데를 가리키게 된다.
    private var emptyRangeTitle: String {
        if selectedDay != nil { return "이 날은 거래가 없어요" }
        if selectedTab == 1 { return "이 달은 입금이 없어요" }
        if selectedTab == 2 { return "이 달은 출금이 없어요" }
        return "이 달은 거래가 없어요"
    }

    private var emptyRangeMessage: String {
        if selectedDay != nil { return "고른 날짜를 다시 누르면 이 달 전체가 보여요." }
        if selectedTab != 0 { return "위 칩에서 '전체'를 누르면 다 보여요." }
        return "헤더의 화살표로 다른 달을 보거나,\n⋯ 에서 거래내역서를 불러오세요."
    }

    /// 당겨서 새로고침. 헤더에 새로고침 버튼이 없다 (DESIGN.md 1번).
    private func reload() async {
        await viewModel.fetchTransactions()
        viewModel.loadSavedStatements()
    }

    private var emptyView: some View {
        EmptyStateView(
            title: "거래내역이 없어요",
            icon: "doc.richtext",
            message: "토스뱅크에서 거래내역서를 공유하면 저장돼요.\n우측 상단 ⋯ 에서 '저장된 거래내역서'를 열어\n'거래내역 불러오기'를 눌러주세요"
        )
        .pullToRefresh { await reload() }
    }

    /// 헤더의 화면별 동작 자리는 하나뿐이라 내보내기·거래내역서를 한 메뉴로 묶는다.
    private func actionMenu(mode: FinanceReportMode) -> some View {
        Menu {
            // 내보내기보다 먼저 둔다 — 확인하고 내보내는 순서가 자연스럽다.
            Button {
                if let html = viewModel.reportHTML() {
                    reportPreview = ReportPreview(html: html, title: mode.title)
                }
            } label: {
                Label("보고서 미리보기", systemImage: "tablecells")
            }
            .disabled(viewModel.filtered.isEmpty)

            Button {
                exportMessage = "보고서 만드는 중…"
                isExporting = true
                Task {
                    // 오버레이가 먼저 그려지도록 한 틱 양보한 뒤 생성
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    let url = viewModel.exportReportPDF()
                    isExporting = false
                    if let url { exportFile = ExportFile(url: url) }
                }
            } label: {
                Label("\(mode.title) (PDF)", systemImage: "doc.text")
            }
            .disabled(viewModel.filtered.isEmpty)

            Button {
                exportMessage = "영수증 내보내는 중…"
                isExporting = true
                Task {
                    let url = await viewModel.exportReceiptsPDF()
                    isExporting = false
                    if let url { exportFile = ExportFile(url: url) }
                }
            } label: {
                Label("영수증 부록 (PDF)", systemImage: "paperclip")
            }
            .disabled(viewModel.filtered.isEmpty)

            Divider()

            Button {
                viewModel.loadSavedStatements()
                showStatements = true
            } label: {
                Label("저장된 거래내역서", systemImage: "folder")
            }
        } label: {
            HeaderIcon(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("더 보기")
    }
}

/// 거래 한 줄.
///
/// **금액이 제목 자리다.** 왼쪽 첫 줄에 크고 굵게 오고, 무엇에 쓴 돈인지는
/// 그 아래 회색 부제로 붙는다. 제목이 왼쪽·금액이 오른쪽이던 적이 있는데,
/// 장부를 훑을 때 눈이 먼저 잡는 건 결국 수다.
///
/// 시각은 뺐다 — 날짜는 섹션 머리가 말하고, 몇 시였는지는 훑을 때 필요한 정보가
/// 아니다. 상세 시트의 "일시" 에 그대로 있다.
struct TransactionRowView: View {
    let transaction: BankTransaction
    var splits: [TransactionSplit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
            // 입금은 브랜드 파랑, 출금은 본문 검정이다. 장부에서 지출은 사고가
            // 아니라 일상이라 경고색을 주지 않는다.
            Text(transaction.isDeposit
                 ? "+\(transaction.amount.formatted())원"
                 : "\(transaction.amount.formatted())원")
                .typeStyle(DS.Typo.title2)
                .tabularAmount()
                .foregroundColor(transaction.isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal)
                .lineLimit(1)

            Text(subtitle)
                .typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.medium)
    }

    /// 금액 아래 한 줄. 거래 이름이 주고, 카테고리가 있으면 가운뎃점으로 잇는다.
    private var subtitle: String {
        let name = transaction.description ?? "-"
        guard let first = categories.first else { return name }
        let category = categories.count > 1 ? "\(first) 외 \(categories.count - 1)" : first
        return "\(name) · \(category)"
    }

    /// 분할이 있으면 그 카테고리들을, 없으면 거래 자체의 카테고리를 쓴다.
    /// 같은 선물비 여러 개는 하나로 합친다.
    private var categories: [String] {
        if splits.isEmpty {
            let c = transaction.category?.trimmingCharacters(in: .whitespaces) ?? ""
            return c.isEmpty ? [] : [c]
        }
        var seen = Set<String>()
        var result: [String] = []
        for split in splits {
            let c = split.category?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = c.isEmpty ? "미분류" : c
            if seen.insert(label).inserted { result.append(label) }
        }
        return result
    }

}
