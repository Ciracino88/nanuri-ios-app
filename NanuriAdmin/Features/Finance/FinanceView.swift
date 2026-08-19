import SwiftUI

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab = 0
    @State private var showDateFilter = false
    @State private var editingTransaction: BankTransaction?
    @State private var showStatements = false
    @State private var exportFile: ExportFile?
    @State private var isExporting = false
    @State private var exportMessage = "내보내는 중…"

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
            // 가운데는 탭 이름이고, 누르면 장부 게이트로 돌아간다 (장부 전환).
            AdminHeaderView(
                title: "재정",
                titleAction: { viewModel.currentLedger = nil },
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
                    if mode == .monthly { dateFilterBar }
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
        }
        .screenBackground()
        .task {
            await viewModel.fetchTransactions()
            viewModel.loadSavedStatements()
        }
    }

    private var dateFilterBar: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\(viewModel.startDate.koreanShortDateString) ~ \(viewModel.endDate.koreanShortDateString)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                showDateFilter = true
            } label: {
                Text("기간 변경")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray6))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDateFilter) {
                DateFilterView(startDate: $viewModel.startDate, endDate: $viewModel.endDate)
            }
        }
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.vertical, 10)
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
                .fontWeight(.medium)
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
        .refreshable { await reload() }
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
                        .fontWeight(.medium)
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
                    .fontWeight(.medium)
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
