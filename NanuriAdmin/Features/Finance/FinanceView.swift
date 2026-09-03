import SwiftUI

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab = 0
    @State private var editingTransaction: BankTransaction?
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    @State private var exportMessage = "내보내는 중…"
    @State private var reportPreview: ReportPreview?
    /// 날짜 셀렉터에서 고른 날. `nil` 이면 이 달 전체다.
    @State private var selectedDay: Date?
    /// 요약 밴드의 "자세히 보기" 가 여는 분석 화면.
    @State private var showSpendingDetail = false
    /// 헤더 왼쪽 통장 버튼이 여는 잔액 화면.
    @State private var showAccounts = false
    /// ⋯ 메뉴가 여는 거래 추가 시트. 농협 거래를 옮겨 적는 자리다.
    @State private var showAddTransaction = false
    /// 분류 붙이기 모드. 켜지면 줄이 "눌러서 고르는 것" 이 된다.
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var showCategorySheet = false

    /// 장부를 고르는 화면이 없다. 통장이 하나라 고를 것이 없고, 하나뿐인 걸 매번
    /// 손으로 고르게 하는 건 아무 뜻이 없다. `start()` 가 받는 즉시 연다.
    ///
    /// 그래서 갈래가 셋이다 — **열어 둔 장부 / 정말 장부가 없음 / 아직 받는 중.**
    /// 뒤의 둘을 안 가르면 받아 오는 사이에 "장부가 없어요" 가 깜빡 스친다.
    var body: some View {
        Group {
            if viewModel.currentLedger != nil {
                content()
            } else if viewModel.ledgersLoaded {
                FinanceLedgerGateView(viewModel: viewModel)
            } else {
                loadingView
            }
        }
        .task { await viewModel.start() }
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            AdminHeaderView(title: "재정")
            Spacer()
            ProgressView()
            Spacer()
        }
        .screenBackground(DS.Surface.card)
    }

    private func content() -> some View {
        VStack(spacing: 0) {
            // 가운데를 **달 넘김**에 내줬다. 탭 이름("재정")은 탭바가 이미 말하고
            // 있고, 이 화면에서 가장 자주 건드리는 건 달이다.
            //
            // 왼쪽은 통장이다. 장부를 고르는 버튼이 있던 자리인데 장부가 하나라
            // 고를 것이 없어졌고, 그 대신 **통장이 둘**이 되면서 잔액을 볼 자리가
            // 필요해졌다. 화면이 어느 장부인지는 여전히 말하지 않는다 — 하나뿐이라
            // 말해 봐야 구별해 주는 게 없다.
            // **알림 종을 안 그린다.** 알림은 "청구가 들어왔다" 는 소식이라 청구서
            // 탭의 것이고, 이 자리는 매달 스무 번 넘게 누르는 거래 추가가 쓴다.
            // 농협은 수기 입력이 유일한 입구라 메뉴 두 단계 안에 둘 자리가 아니다.
            AdminHeaderView(
                showsNotifications: false,
                center: { monthStepper },
                leading: {
                    if isSelecting {
                        HeaderIconButton(systemName: "xmark", label: "고르기 그만두기",
                                         tint: DS.Palette.accent) { exitSelection() }
                    } else {
                        HeaderIconButton(systemName: "wallet.bifold", label: "통장 잔액") {
                            showAccounts = true
                        }
                    }
                },
                trailing: {
                    // 고르는 중에는 다른 동작을 걷는다. 지금 할 일은 하나다.
                    if !isSelecting {
                        actionMenu()
                        HeaderIconButton(systemName: "plus", label: "거래 추가") {
                            showAddTransaction = true
                        }
                    }
                }
            )

            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.transactions.isEmpty {
                    emptyView
                } else {
                    scrollingContent()
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
            // 공유로 들어오면 목록을 거치지 않고 여기서 바로 뜬다.
            .sheet(item: $viewModel.incomingStatement) { incoming in
                if let account = viewModel.account(named: "모임") {
                    StatementImportView(viewModel: viewModel, url: incoming.url, account: account)
                }
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .sheet(item: $reportPreview) { preview in
                FinanceReportPreviewView(html: preview.html, title: preview.title)
            }
            .sheet(isPresented: $showSpendingDetail) {
                SpendingDetailView(viewModel: viewModel)
            }
            .sheet(isPresented: $showAccounts) {
                AccountBalanceView(viewModel: viewModel)
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView(viewModel: viewModel)
            }
            .sheet(isPresented: $showCategorySheet) {
                CategoryAssignView(suggestions: viewModel.usedCategories,
                                   count: selection.count) { category in
                    Task {
                        await viewModel.applyCategory(category, to: selectedRows)
                        exitSelection()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
        }
        // 목록이 흰 바탕에 그냥 앉는 구조라 페이지가 흰색이다. 회색으로 서는 건
        // 요약 밴드 하나뿐이고, 그 대비가 화면 위쪽을 잡아 준다.
        .screenBackground(DS.Surface.card)
        .task {
            await viewModel.fetchTransactions()
        }
    }

    /// 고른 줄들. 화면에 안 보이는 달의 줄은 애초에 못 고른다.
    private var selectedRows: [LedgerRow] {
        viewModel.ledgerRows.filter { selection.contains($0.id) }
    }

    private func toggle(_ row: LedgerRow) {
        if selection.contains(row.id) { selection.remove(row.id) } else { selection.insert(row.id) }
    }

    private func enterSelection() {
        selection = []
        withAnimation(DS.Motion.control) { isSelecting = true }
    }

    private func exitSelection() {
        withAnimation(DS.Motion.control) { isSelecting = false }
        selection = []
    }

    /// 고르는 중에 바닥에 서는 바. 묶어 보내기의 `selectionBar` 와 같은 문법이다.
    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: DS.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection.isEmpty ? "분류를 붙일 줄을 고르세요" : "\(selection.count)줄 선택")
                        .rowTitle()
                    Spacer(minLength: DS.Spacing.small)
                    // **아무것도 안 골랐을 때 가장 쓸모 있다.** 분류를 붙이는 일은
                    // 대개 "남은 것 전부" 로 시작해서 몇 줄을 빼는 식이다.
                    if !viewModel.uncategorizedRows.isEmpty {
                        Button("미분류 전체") {
                            selection = Set(viewModel.uncategorizedRows.map(\.id))
                        }
                        .typeStyle(DS.Typo.labelS)
                        .foregroundColor(DS.Ink.brand)
                    }
                }
                if !selection.isEmpty {
                    ActionButton(title: "분류 붙이기", kind: .primary) { showCategorySheet = true }
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.medium)
            .padding(.bottom, DS.Spacing.small)
        }
        .background(DS.Surface.card)
        .elevation(.bottomBar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    /// 눈으로 읽을 수 있고, 통장 잔액은 헤더 왼쪽의 통장 화면(`AccountBalanceView`)
    /// 에 있다 — 여기 두 수가 **이 달에 오간 돈**인 데 반해 잔액은 **쌓인 돈**이라
    /// 나란히 서면 같은 종류의 수로 읽힌다.
    ///
    /// **라벨이 위, 숫자가 아래다.** 여기서는 "무엇의 수인지"를 먼저 알아야
    /// 수가 읽힌다.
    private func summaryBand() -> some View {
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

    private var currentItems: [LedgerRow] {
        let byKind: [LedgerRow]
        switch selectedTab {
        case 1: byKind = viewModel.depositRows
        case 2: byKind = viewModel.withdrawalRows
        case 3: byKind = viewModel.uncategorizedRows
        default: byKind = viewModel.ledgerRows
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
        for row in currentItems {
            let day = calendar.startOfDay(for: row.datetime)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(row)
            } else {
                groups.append(DayGroup(day: day, items: [row]))
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
    private func scrollingContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 레퍼런스 순서 그대로 — 거르개가 먼저, 요약이 그다음, 날짜 축이
                // 그 아래, 목록이 맨 끝이다. 위에서 아래로 범위가 좁혀진다.
                // 개수는 **장부 줄 수**다. 묶어 보낸 출금 하나가 조각 아홉이면
                // 아홉으로 센다 — 엑셀 장부의 줄 수와 같은 수라야 한다.
                // **미분류가 넷째 칸이다.** 분류를 붙이는 일은 "남은 것" 을 보는
                // 일이라 그 수가 보여야 한다. 내부 이체는 안 센다 — 앞으로도 분류가
                // 안 붙는 줄이라 세면 그 수가 영영 0이 안 된다.
                ChipSelector(items: [
                    .init(value: 0, label: "전체", count: viewModel.ledgerRows.count),
                    .init(value: 1, label: "입금", count: viewModel.depositRows.count),
                    .init(value: 2, label: "출금", count: viewModel.withdrawalRows.count),
                    .init(value: 3, label: "미분류", count: viewModel.uncategorizedRows.count)
                ], selection: $selectedTab)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.s5)

                summaryBand()

                daySelector

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

            ForEach(group.items) { row in
                // 고르는 중이면 누르는 뜻이 바뀐다 — 시트를 여는 대신 고른다.
                // 조각을 눌러도 **부모 거래**의 편집이 열린다. 고칠 것이 조각
                // 하나여도 금액·통장·영수증은 거래가 갖고 있다.
                LedgerRowView(row: row,
                              isSelected: isSelecting ? selection.contains(row.id) : nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting { toggle(row) } else { editingTransaction = row.transaction }
                    }
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
    /// 통장도 같이 다시 받는다. 통장이 안 받아졌으면 개시잔액이 0이 되어 잔액과
    /// 전월이월이 통째로 틀리는데, 그때 사람이 하는 동작이 당겨서 새로고침이다.
    private func reload() async {
        await viewModel.fetchAccounts()
        await viewModel.fetchTransactions()
    }

    private var emptyView: some View {
        EmptyStateView(
            title: "거래내역이 없어요",
            icon: "doc.richtext",
            message: "우측 상단 ＋ 로 직접 넣거나,\n토스뱅크 거래내역서를 앱으로 공유하면 돼요"
        )
        .pullToRefresh { await reload() }
    }

    /// 내보내는 것들만 모은 메뉴. **거래 추가는 여기 없다** — 헤더로 나갔다.
    ///
    /// 예전에는 이 메뉴 맨 위에 있었다. 알림 종이 오른쪽 자리를 늘 차지하고 있어서
    /// 헤더에 아이콘을 하나 더 둘 수 없었기 때문인데, 재정 탭에서 그 종을 빼면서
    /// 자리가 났다. **장부를 쓰는 게 이 화면의 본업이고 나머지는 뽑는 일이다.**
    private func actionMenu() -> some View {
        Menu {
            // **맨 위다.** 분류를 붙이는 건 장부를 쓰는 일이고 나머지는 뽑는 일이다.
            Button {
                enterSelection()
            } label: {
                Label("분류 붙이기", systemImage: "checklist")
            }
            .disabled(viewModel.ledgerRows.isEmpty)

            Divider()

            // 내보내기보다 먼저 둔다 — 확인하고 내보내는 순서가 자연스럽다.
            Button {
                if let html = viewModel.reportHTML() {
                    reportPreview = ReportPreview(html: html, title: "월별 회계 보고서")
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
                Label("월별 회계 보고서 (PDF)", systemImage: "doc.text")
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

        } label: {
            HeaderIcon(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("더 보기")
    }
}

/// **장부 한 줄.**
///
/// **금액이 제목 자리다.** 왼쪽 첫 줄에 크고 굵게 오고, 무엇에 쓴 돈인지는
/// 그 아래 회색 부제로 붙는다. 제목이 왼쪽·금액이 오른쪽이던 적이 있는데,
/// 장부를 훑을 때 눈이 먼저 잡는 건 결국 수다.
///
/// **거래가 아니라 조각을 그린다.** 묶어 보낸 출금 하나는 여기서 여러 줄이 된다 —
/// 사람이 쓰던 엑셀이 그 모양이고, 보고서·분석도 이미 그 단위로 센다.
///
/// 시각은 뺐다 — 날짜는 섹션 머리가 말하고, 몇 시였는지는 훑을 때 필요한 정보가
/// 아니다. 상세 시트의 "일시" 에 그대로 있다.
struct LedgerRowView: View {
    let row: LedgerRow
    /// 고르는 중일 때만 값이 있다. `nil` 이면 평소 목록이다.
    var isSelected: Bool?

    var body: some View {
        HStack(spacing: DS.Spacing.medium) {
            if let isSelected {
                // 청구서 탭 선택 모드와 같은 표식이다.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DS.Icon.font(DS.Icon.action))
                    .foregroundColor(isSelected ? DS.Palette.accent : DS.Ink.placeholder)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.medium)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
            // 입금은 브랜드 파랑, 출금은 본문 검정이다. 장부에서 지출은 사고가
            // 아니라 일상이라 경고색을 주지 않는다.
            //
            // **통장 사이 이체는 셋째 색이다.** 수입도 지출도 아니라서 — 장부
            // 전체로 보면 나간 돈도 들어온 돈도 아니고 합계·보고서에서도 빠진다.
            // 파랑이나 검정을 주면 그 줄이 다른 줄과 같은 종류의 수로 읽힌다.
            Text(row.isDeposit
                 ? "+\(row.amount.formatted())원"
                 : "\(row.amount.formatted())원")
                .typeStyle(DS.Typo.title2)
                .tabularAmount()
                .foregroundColor(amountColor)
                .lineLimit(1)

            Text(subtitle)
                .typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 금액의 색. 입금 파랑 · 출금 검정 · **통장 사이 이체는 회색**이다.
    private var amountColor: Color {
        if row.isInternalTransfer { return DS.Ink.tertiary }
        return row.isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }

    /// 금액 아래 한 줄. **장부 적요 · 카테고리** 순이다.
    ///
    /// 은행이 찍은 적요를 앞에 두던 적이 있는데(`이충성 · 볼링 게임 우승 상품`),
    /// 그건 **장부를 훑는 사람이 알고 싶은 순서가 아니다.** 이 목록은 통장이 아니라
    /// 장부고, 장부에 적힌 이름이 먼저 와야 한다. 은행 적요는 상세에 있다.
    ///
    /// **카테고리가 비면 가운뎃점째로 안 나온다.** 거래내역서로 들어온 조각은
    /// 분류가 비어 있는데, 거기에 "미분류" 를 적으면 목록이 그 글자로 뒤덮인다.
    private var subtitle: String {
        // 내부 이체에는 장부 줄(분할)이 없다. 대신 성격을 말한다.
        if row.isInternalTransfer { return "통장 사이 이체" }
        let head = clean(row.title) ?? "-"
        guard let tail = clean(row.category) else { return head }
        return "\(head) · \(tail)"
    }

    private func clean(_ value: String?) -> String? {
        let v = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? nil : v
    }
}


/// 고른 줄들에 붙일 분류를 정하는 시트.
///
/// **이미 쓴 이름을 먼저 보여준다.** 새로 치는 것보다 고르는 게 빠르고, 같은 뜻에
/// 이름이 둘 생기는 것(`행사비`·`행사 비용`)을 막는다 — 그러면 보고서 요약이
/// 두 줄로 갈린다.
private struct CategoryAssignView: View {
    let suggestions: [String]
    let count: Int
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("카테고리 (예: 회비, 행사비, 심방비)", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                } footer: {
                    Text("\(count)줄에 같이 붙어요. 비워 두고 누르면 분류가 지워져요.")
                }
            }
            .navigationTitle("분류 붙이기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("붙이기") {
                        onApply(category)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
