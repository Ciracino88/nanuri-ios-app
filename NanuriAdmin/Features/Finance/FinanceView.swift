import SwiftUI

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab = 0
    /// 탭한 **항목**. 거래가 아니라 항목(조각일 수도, 거래 전체일 수도)을 넘긴다 —
    /// 편집 화면이 조각을 눌렀는지 알아야 그 조각을 보여줄 수 있다.
    @State private var editingRow: LedgerRow?
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
    /// 선택 모드. 켜지면 항목이 "눌러서 고르는 것" 이 되고, 아래 바에서 병합·삭제·
    /// 카테고리 중 하나를 한다.
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var showCategorySheet = false
    @State private var showMergeInput = false
    @State private var mergeDescription = ""
    @State private var showDeleteSelectedConfirm = false
    /// 햄버거(≡)가 여는 풀스크린 메뉴.
    @State private var showMenu = false
    /// 메뉴에서 고른 동작. 메뉴가 닫힌 **뒤에** 실행한다 — 풀스크린 위에 바로
    /// 다른 시트를 얹으면 둘이 부딪혀 조용히 안 뜬다. `onDismiss` 가 이걸 집어 연다.
    @State private var pendingMenuAction: FinanceMenuAction?

    /// 통장은 마이그레이션에서 심겨 늘 둘이라, 고르거나 만드는 화면이 없다.
    /// 받는 중이면 로딩, 다 받으면 바로 장부를 연다.
    var body: some View {
        Group {
            if viewModel.loaded {
                content()
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
            // 인스타그램 프로필 헤더의 문법 — **왼쪽은 만들기, 오른쪽은 관리**다.
            // 가운데는 달 넘김이 가져간다(탭 이름은 탭바가 이미 말한다). 왼쪽엔
            // 매달 스무 번 넘게 누르는 거래 추가를, 오른쪽엔 가끔 쓰는 것(카테고리
            // 추가 · 통장 잔액 · 내보내기)을 모은다.
            //
            // **알림 종은 안 그린다**(`showsNotifications: false`). 알림은 "청구가
            // 들어왔다" 는 소식이라 청구서 탭의 것이다. 통장 잔액은 헤더 왼쪽을
            // 거래 추가에 내주고 ⋯ 메뉴 첫 줄로 들어갔다.
            AdminHeaderView(
                showsNotifications: false,
                center: { FinanceMonthStepper(viewModel: viewModel) },
                leading: {
                    if isSelecting {
                        // 선택 모드를 끄는 것뿐 화면은 안 닫는다 → 취소(xmark) 버튼.
                        HeaderCancelButton(label: "고르기 그만두기") { exitSelection() }
                    } else {
                        HeaderIconButton(systemName: "plus", label: "거래 추가") {
                            showAddTransaction = true
                        }
                    }
                },
                trailing: {
                    // 고르는 중에는 다른 동작을 걷는다. 지금 할 일은 하나다.
                    if !isSelecting {
                        // 선택 모드는 이제 메뉴 안이 아니라 헤더의 제 버튼이다 —
                        // 장부를 쓰는 본업이라 두 단계 안에 숨길 자리가 아니다.
                        // 고른 뒤 아래 바에서 병합·삭제·카테고리 중 하나를 한다.
                        HeaderIconButton(systemName: "checklist", label: "항목 고르기") {
                            enterSelection()
                        }
                        .disabled(viewModel.ledgerRows.isEmpty)
                        // 햄버거(≡)는 드롭다운이 아니라 **풀스크린 메뉴**로 빠진다
                        // (인스타그램 프로필의 ≡ 문법). 통장 잔액·내보내기가 거기 모인다.
                        HeaderIconButton(systemName: "line.3.horizontal", label: "메뉴") {
                            showMenu = true
                        }
                    }
                }
            )

            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.items.isEmpty {
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
            // 타이틀이 필요한 화면이라 시트가 아니라 풀스크린이다 (DESIGN.md §1).
            .fullScreenCover(item: $editingRow) { row in
                ItemEditView(row: row, suggestions: viewModel.usedCategories, viewModel: viewModel)
            }
            // 공유로 들어오면 목록을 거치지 않고 여기서 바로 뜬다.
            // 시트가 아니라 풀스크린이다 — 확인 화면이 상세를 push 로 받는다
            // (레퍼런스식 내비게이션, DESIGN.md §13). AddTransactionView 와 같은 문법.
            .fullScreenCover(item: $viewModel.incomingStatement) { incoming in
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
            // 토스처럼 풀스크린으로 연다 (시트 아님).
            .fullScreenCover(isPresented: $showAddTransaction) {
                AddTransactionView(viewModel: viewModel)
            }
            // 드롭다운이 아니라 화면을 통째로 덮는 풀스크린이다. 닫힌 뒤 고른 동작을
            // 잇는다(`runPendingMenuAction`) — 풀스크린 위에 시트를 바로 얹지 못해서다.
            .fullScreenCover(isPresented: $showMenu, onDismiss: runPendingMenuAction) {
                FinanceMenuView(hasData: !viewModel.filtered.isEmpty) { action in
                    pendingMenuAction = action
                    showMenu = false
                }
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
            // 병합: 합쳐질 항목의 적요를 새로 입력받는다 (c안).
            .alert("합쳐서 적을 이름", isPresented: $showMergeInput) {
                TextField("적요 (예: 8월 심방비 모음)", text: $mergeDescription)
                Button("병합") {
                    Task {
                        await viewModel.mergeItems(selectedRows, description: mergeDescription)
                        exitSelection()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("고른 \(selection.count)개 항목을 한 줄로 합쳐요. 금액은 합이 되고, 영수증은 모두 옮겨져요.")
            }
            .confirmationDialog("고른 항목을 삭제할까요?", isPresented: $showDeleteSelectedConfirm, titleVisibility: .visible) {
                Button("\(selection.count)개 삭제", role: .destructive) {
                    Task {
                        await viewModel.deleteItems(selectedRows)
                        exitSelection()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("영수증까지 함께 지워져요. 되돌릴 수 없어요.")
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
        }
        // 목록이 흰 바탕에 그냥 앉는 구조라 페이지가 흰색이다. 회색으로 서는 건
        // 요약 밴드 하나뿐이고, 그 대비가 화면 위쪽을 잡아 준다.
        .screenBackground(DS.Surface.card)
        // 선택 모드에서는 하단 탭바를 숨긴다 — 아래 선택 바(`selectionBar`)가 그
        // 자리를 쓰고, 고르는 동안엔 탭을 옮길 일이 없다 (청구서 탭과 같은 규칙).
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
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

    /// 고른 항목들.
    private var selectedItems: [FinanceItem] { selectedRows.map(\.item) }

    /// 병합할 수 있는 선택인가. **농협 수기 항목만**(은행 증명 없음), 같은 통장·같은
    /// 방향, 둘 이상일 때. 뷰모델도 저장 직전에 한 번 더 막는다.
    private var canMerge: Bool {
        let items = selectedItems
        guard items.count >= 2,
              items.allSatisfy({ $0.sourceTransactionId == nil && !$0.isInternalTransfer }),
              let acc = items.first?.accountId, items.allSatisfy({ $0.accountId == acc })
        else { return false }
        return items.allSatisfy { $0.amount > 0 } || items.allSatisfy { $0.amount < 0 }
    }

    /// 고르는 중에 바닥에 서는 바. 골라 둔 게 있으면 **병합·삭제·카테고리** 셋을 준다.
    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: DS.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection.isEmpty ? "항목을 고르세요" : "\(selection.count)줄 선택")
                        .rowTitle()
                    Spacer(minLength: DS.Spacing.small)
                    if !viewModel.uncategorizedRows.isEmpty {
                        Button("미지정 전체") {
                            selection = Set(viewModel.uncategorizedRows.map(\.id))
                        }
                        .typeStyle(DS.Typo.labelS)
                        .foregroundColor(DS.Ink.brand)
                    }
                }
                if !selection.isEmpty {
                    HStack(spacing: DS.Spacing.small) {
                        ActionButton(title: "병합", kind: .tinted) {
                            mergeDescription = ""
                            showMergeInput = true
                        }
                        .disabled(!canMerge)
                        ActionButton(title: "삭제", kind: .destructive) { showDeleteSelectedConfirm = true }
                        ActionButton(title: "카테고리", kind: .primary) { showCategorySheet = true }
                    }
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

    /// 정렬 줄. **오른쪽 끝에 붙는다** — 왼쪽은 날짜 셀렉터가 이미 다 쓴 폭이라
    /// 비어 있고, 정렬은 목록의 성질이라 목록 바로 위 오른쪽에 있어야 눈이 잇는다.
    ///
    /// 두 갈래뿐이라(최신순·오래된 순) 메뉴로 고르게 하지 않고 **눌러서 바로
    /// 뒤집는 토글**이다 — 옵션을 펼쳐 다시 한 번 고르는 손품이 없다. 라벨은
    /// 지금 무슨 순인지를 적고, 누르면 반대 순으로 바뀐다. 정렬 자체는 뷰모델의
    /// `oldestFirst` 한 값이 갖는다.
    private var sortRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Motion.list) { viewModel.oldestFirst.toggle() }
            } label: {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(DS.Icon.font(DS.Icon.s))
                    Text(viewModel.oldestFirst ? "오래된 순" : "최신순")
                        .typeStyle(DS.Typo.labelS)
                }
                .foregroundColor(DS.Ink.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("정렬 순서")
            .accessibilityValue(viewModel.oldestFirst ? "오래된 순" : "최신순")
            .accessibilityHint("두 번 누르면 정렬 순서를 바꿔요")
        }
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.bottom, DS.Spacing.small)
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
                // 개수는 **항목 수**다. 묶어 보낸 출금 하나가 조각 아홉이면
                // 아홉으로 센다 — 엑셀 장부의 줄 수와 같은 수라야 한다.
                // **미지정이 넷째 칸이다.** 카테고리를 붙이는 일은 "남은 것" 을 보는
                // 일이라 그 수가 보여야 한다. 내부 이체는 안 센다 — 앞으로도 카테고리가
                // 안 붙는 줄이라 세면 그 수가 영영 0이 안 된다.
                ChipSelector(items: [
                    .init(value: 0, label: "전체", count: viewModel.ledgerRows.count),
                    .init(value: 1, label: "입금", count: viewModel.depositRows.count),
                    .init(value: 2, label: "출금", count: viewModel.withdrawalRows.count),
                    .init(value: 3, label: "미지정", count: viewModel.uncategorizedRows.count)
                ], selection: $selectedTab)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.s5)

                FinanceSummaryBand(viewModel: viewModel, showSpendingDetail: $showSpendingDetail)

                FinanceDaySelector(viewModel: viewModel, selectedDay: $selectedDay)

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
                    // 정렬 줄은 **목록이 있을 때만** 뜬다 — 빈 범위 위에 정렬
                    // 컨트롤이 홀로 서 있으면 무엇을 정렬하는 건지 알 수 없다.
                    sortRow
                    ForEach(dayGroups) { group in
                        daySection(group)
                    }
                }
            }
            .padding(.bottom, DS.Spacing.s8)
            .animation(DS.Motion.list, value: selectedTab)
            .animation(DS.Motion.list, value: viewModel.currentMonth)
            .animation(DS.Motion.list, value: selectedDay)
            .animation(DS.Motion.list, value: viewModel.oldestFirst)
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
                // **누른 줄(조각) 그대로 넘긴다.** 편집 화면이 조각을 중심으로
                // 보여주고, 금액·통장·영수증·삭제는 "속한 출금 전체" 로 밝힌다.
                LedgerRowView(row: row,
                              isSelected: isSelecting ? selection.contains(row.id) : nil)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelecting { toggle(row) } else { editingRow = row }
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
    /// 풀스크린 메뉴가 닫힌 **뒤** 고른 동작을 실행한다.
    ///
    /// 내보내기 기계(진행 오버레이 · `ShareSheet` · 보고서 생성)는 전부 이 화면이
    /// 갖고 있어서, 메뉴는 "무엇을 고를지" 만 넘기고 실행은 여기 한자리에 둔다.
    private func runPendingMenuAction() {
        guard let action = pendingMenuAction else { return }
        pendingMenuAction = nil
        switch action {
        case .accounts:
            showAccounts = true
        case .reportPreview:
            if let html = viewModel.reportHTML() {
                reportPreview = ReportPreview(html: html, title: "월별 회계 보고서")
            }
        case .exportReportPDF:
            exportMessage = "보고서 만드는 중…"
            isExporting = true
            Task {
                // 오버레이가 먼저 그려지도록 한 틱 양보한 뒤 생성
                try? await Task.sleep(nanoseconds: 30_000_000)
                let url = viewModel.exportReportPDF()
                isExporting = false
                if let url { exportFile = ExportFile(url: url) }
            }
        case .exportReceiptsPDF:
            exportMessage = "영수증 내보내는 중…"
            isExporting = true
            Task {
                let url = await viewModel.exportReceiptsPDF()
                isExporting = false
                if let url { exportFile = ExportFile(url: url) }
            }
        }
    }
}
