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
        return NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.transactions.isEmpty {
                    emptyView
                } else {
                    if mode == .monthly { dateFilterBar }
                    summaryCard
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
            .navigationTitle(ledger.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.currentLedger = nil
                    } label: {
                        Image(systemName: "rectangle.2.swap")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
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
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .disabled(viewModel.filtered.isEmpty)

                        Button {
                            viewModel.loadSavedStatements()
                            showStatements = true
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 18, weight: .medium))
                        }
                    }
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
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            summaryItem(label: "총 입금", amount: viewModel.totalDeposit, color: .blue)
            Divider().frame(height: 40)
            summaryItem(label: "총 출금", amount: viewModel.totalWithdrawal, color: .red)
            Divider().frame(height: 40)
            summaryItem(label: "잔액", amount: viewModel.totalDeposit - viewModel.totalWithdrawal, color: .primary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onTapGesture { editingTransaction = tx }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("거래내역이 없어요")
                .font(.title3)
                .fontWeight(.medium)
            Text("토스뱅크에서 거래내역서를 공유하면 저장돼요.\n우측 상단 폴더에서 열어 '거래내역 불러오기'를 눌러주세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
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
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.isDeposit ? .blue : .red)
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
                    .font(.caption2)
                    .foregroundColor(.blue)
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
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
        Text(text).tagChip(color: .blue)
    }
}
