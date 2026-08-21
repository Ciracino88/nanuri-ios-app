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
            // 가운데는 탭 이름이고, 누르면 장부를 고르는 시트가 열린다.
            // ▾ 는 펼쳐진다는 뜻이라 되돌아가는 동작을 걸어 두면 눌러 봐야 알게 된다.
            AdminHeaderView(
                title: "재정",
                titleAction: { showSwitcher = true },
                trailing: { actionMenu(mode: mode) }
            )

            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.transactions.isEmpty {
                    emptyView
                } else {
                    if mode == .monthly { monthBar }
                    summaryCard(ledger: ledger)
                    PillPicker(
                        tabs: [
                            ("전체", viewModel.filtered.count),
                            ("입금", viewModel.deposits.count),
                            ("출금", viewModel.withdrawals.count)
                        ],
                        selection: $selectedTab
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                    transactionList
                }
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(exportMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
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
        .screenBackground()
        .task {
            await viewModel.fetchTransactions()
            viewModel.loadSavedStatements()
        }
    }

    /// 달을 하나씩 넘기는 줄. 수기 장부가 시트 하나 = 한 달이었던 그대로다.
    /// 가운데를 누르면 달 목록에서 바로 건너뛴다 (20개월을 한 칸씩 넘기지 않아도 되게).
    private var monthBar: some View {
        HStack(spacing: DS.Spacing.small) {
            monthStep(systemName: "chevron.left",
                      label: "이전 달",
                      enabled: viewModel.canGoToPreviousMonth) {
                viewModel.goToPreviousMonth()
            }

            Menu {
                // 최근 달이 위로 오게 뒤집는다 — 보통 찾는 건 가까운 달이다.
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
                HStack(spacing: DS.Spacing.tight) {
                    Text(viewModel.currentMonth.koreanYearMonthString)
                        .rowTitle()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("달 고르기")

            monthStep(systemName: "chevron.right",
                      label: "다음 달",
                      enabled: viewModel.canGoToNextMonth) {
                viewModel.goToNextMonth()
            }
        }
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.vertical, DS.Spacing.small)
        .animation(DS.Motion.control, value: viewModel.currentMonth)
    }

    private func monthStep(systemName: String, label: String,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: DS.Icon.inline, weight: .semibold))
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .background(Color(.systemGray6))
                .foregroundColor(enabled ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    /// 헤더 가운데가 탭 이름("재정")이 되면서 지금 보고 있는 장부 이름이 갈 곳이
    /// 없어졌다. 요약 카드 첫 줄이 그 자리다 — 금액을 볼 때 어느 통장인지 같이 보인다.
    private func summaryCard(ledger: Ledger) -> some View {
        VStack(spacing: DS.Spacing.medium) {
            HStack(spacing: DS.Spacing.small) {
                Image(systemName: ledger.mode.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(ledger.name)
                    .rowSubtext()
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                summaryItem(label: "총 입금", amount: viewModel.totalDeposit, color: DS.Palette.deposit)
                Divider().frame(height: 40)
                summaryItem(label: "총 출금", amount: viewModel.totalWithdrawal, color: DS.Palette.withdrawal)
                Divider().frame(height: 40)
                summaryItem(label: "잔액", amount: viewModel.totalDeposit - viewModel.totalWithdrawal, color: .primary)
            }
        }
        .cardStyle()
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.vertical, DS.Spacing.small)
    }

    private func summaryItem(label: String, amount: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(abs(amount).formatted())원")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentItems: [BankTransaction] {
        switch selectedTab {
        case 1: return viewModel.deposits
        case 2: return viewModel.withdrawals
        default: return viewModel.filtered
        }
    }

    private var transactionList: some View {
        List(currentItems) { tx in
            TransactionRowView(transaction: tx, splits: viewModel.splits(for: tx.id))
                .cardRow()
                .onTapGesture { editingTransaction = tx }
        }
        .listStyle(.plain)
        .screenBackground()
        .animation(DS.Motion.list, value: selectedTab)
        .animation(DS.Motion.list, value: viewModel.currentMonth)
        .refreshable { await reload() }
        // 장부 전체가 아니라 **이 달만** 비어 있는 경우다. 전체 빈 화면으로 덮으면
        // 달 넘기는 줄까지 사라져서 빠져나갈 길이 없어진다. 목록 자리에만 얹는다.
        .overlay {
            if currentItems.isEmpty {
                EmptyStateView(
                    title: "이 달은 거래가 없어요",
                    message: "위 화살표로 다른 달을 보거나,\n⋯ 에서 거래내역서를 불러오세요."
                )
                .allowsHitTesting(false)
            }
        }
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

struct TransactionRowView: View {
    let transaction: BankTransaction
    var splits: [TransactionSplit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.description ?? "-")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !splits.isEmpty {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(distinctCategories, id: \.self) { category in
                                chip(category)
                            }
                        }
                    } else if let category = transaction.category, !category.isEmpty {
                        chip(category)
                    }
                }
                Spacer()
                Text(transaction.isDeposit ? "+\(transaction.amount.formatted())원" : "\(transaction.amount.formatted())원")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal)
            }
            HStack {
                Text(transaction.datetime.koreanDateTimeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !transaction.receipts.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "paperclip")
                        Text("\(transaction.receipts.count)")
                    }
                    .font(.caption)
                    .foregroundColor(DS.Palette.deposit)
                }
                Spacer()
                Text("잔액 \(transaction.balance.formatted())원")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let memo = transaction.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    /// 분할 항목들의 카테고리를 중복 제거해 순서대로 반환 (같은 선물비 여러 개는 하나로).
    private var distinctCategories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for split in splits {
            let c = split.category?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = c.isEmpty ? "미분류" : c
            if seen.insert(label).inserted { result.append(label) }
        }
        return result
    }

    private func chip(_ text: String) -> some View {
        Text(text).tagChip(color: DS.Palette.deposit)
    }
}
