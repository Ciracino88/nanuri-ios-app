import SwiftUI
import PDFKit

struct FinanceView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab = 0
    @State private var showDateFilter = false
    @State private var editingTransaction: BankTransaction?
    @State private var showStatements = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewModel.transactions.isEmpty {
                    emptyView
                } else {
                    dateFilterBar
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
            .navigationTitle("재정 관리")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.loadSavedStatements()
                        showStatements = true
                    } label: {
                        Image(systemName: "folder")
                    }
                }
            }
            .alert("오류", isPresented: .constant(viewModel.error != nil)) {
                Button("확인") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(item: $editingTransaction) { tx in
                TransactionEditView(transaction: tx, suggestions: viewModel.usedCategories) { category, memo in
                    Task { await viewModel.updateTransaction(id: tx.id, category: category, memo: memo) }
                }
            }
            .sheet(isPresented: $showStatements) {
                StatementsListView(viewModel: viewModel)
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
            summaryItem(label: "순수익", amount: viewModel.totalDeposit - viewModel.totalWithdrawal, color: .primary)
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
            TransactionRowView(transaction: tx)
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
            Text("토스뱅크 앱에서 거래내역서를\n공유하기로 이 앱에 전달해주세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

struct TransactionRowView: View {
    let transaction: BankTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.description ?? "-")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let category = transaction.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
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
}

struct DateFilterView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                DatePicker("종료일", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
            .navigationTitle("기간 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}

struct StatementsListView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var previewStatement: StatementFile?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.savedStatements.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("보관된 거래내역서가 없어요")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.savedStatements) { statement in
                            Button {
                                previewStatement = statement
                            } label: {
                                HStack {
                                    Image(systemName: "doc.richtext")
                                        .foregroundColor(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(statement.importedAt.koreanDateString)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(statement.importedAt.koreanTimeString + " 가져옴")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    ShareLink(item: statement.url) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.plain)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            indexSet.map { viewModel.savedStatements[$0] }
                                .forEach { viewModel.deleteStatement($0) }
                        }
                    }
                }
            }
            .navigationTitle("저장된 거래내역서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(item: $previewStatement) { statement in
                StatementDetailView(statement: statement, viewModel: viewModel)
            }
        }
    }
}

/// 보관된 거래내역서 원본을 앱 안에서 미리보고, 다시 파싱할 수 있는 화면.
struct StatementDetailView: View {
    let statement: StatementFile
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showReparseResult = false

    var body: some View {
        NavigationView {
            PDFKitView(url: statement.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(statement.importedAt.koreanDateString)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("닫기") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            viewModel.reparseStatement(statement)
                            showReparseResult = true
                        } label: {
                            Label("다시 불러오기", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .alert("다시 불러오기", isPresented: $showReparseResult) {
                    Button("확인") { dismiss() }
                } message: {
                    Text("이 거래내역서를 다시 파싱해 거래내역을 갱신했어요.")
                }
        }
    }
}

/// PDFKit 기반 PDF 뷰어 래퍼.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

struct TransactionEditView: View {
    let transaction: BankTransaction
    let suggestions: [String]
    let onSave: (String?, String?) -> Void

    @State private var category: String
    @State private var memo: String
    @Environment(\.dismiss) var dismiss

    init(transaction: BankTransaction, suggestions: [String], onSave: @escaping (String?, String?) -> Void) {
        self.transaction = transaction
        self.suggestions = suggestions
        self.onSave = onSave
        _category = State(initialValue: transaction.category ?? "")
        _memo = State(initialValue: transaction.memo ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("거래 정보") {
                    LabeledContent("내용", value: transaction.description ?? "-")
                    LabeledContent("금액", value: "\(transaction.amount.formatted())원")
                    LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
                }
                Section("분류") {
                    TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $category)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        category = suggestion
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(category == suggestion ? Color.blue : Color(.systemGray6))
                                            .foregroundColor(category == suggestion ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    TextField("메모", text: $memo, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("거래 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        onSave(category.isEmpty ? nil : category, memo.isEmpty ? nil : memo)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
