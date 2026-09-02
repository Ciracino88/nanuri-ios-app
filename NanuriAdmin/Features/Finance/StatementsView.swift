import SwiftUI
import PDFKit

struct StatementsListView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var previewStatement: StatementFile?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.savedStatements.isEmpty {
                    EmptyStateView(title: "보관된 거래내역서가 없어요", icon: "folder")
                } else {
                    List {
                        ForEach(viewModel.savedStatements) { statement in
                            Button {
                                previewStatement = statement
                            } label: {
                                HStack {
                                    Image(systemName: "doc.richtext")
                                        .font(DS.Icon.font(DS.Icon.l))
                                        .foregroundColor(DS.Ink.brand)
                                    VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                                        Text(statement.importedAt.koreanDateString)
                                            .rowTitle()
                                        Text(statement.importedAt.koreanTimeString + " 가져옴")
                                            .rowSubtext()
                                    }
                                    Spacer()
                                    ShareLink(item: statement.url) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.plain)
                                    Image(systemName: "chevron.right")
                                        .font(DS.Icon.font(DS.Icon.m))
                                        .foregroundColor(DS.Ink.placeholder)
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
    @State private var showImport = false
    @State private var missingAccount = false

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
                            // 곧바로 저장하지 않는다. 청구서와 맞춰 적요·분할까지
                            // 만들어 내므로 사람이 한 번 보고 넘어가야 한다.
                            if viewModel.account(named: "모임") == nil {
                                missingAccount = true
                            } else {
                                showImport = true
                            }
                        } label: {
                            Label("거래내역 불러오기", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                // 토스에서 뽑은 내역서라 모임통장 것이다.
                .sheet(isPresented: $showImport) {
                    if let account = viewModel.account(named: "모임") {
                        StatementImportView(viewModel: viewModel,
                                            statement: statement,
                                            account: account)
                    }
                }
                .alert("모임통장을 찾을 수 없어요", isPresented: $missingAccount) {
                    Button("확인") {}
                } message: {
                    Text("장부에 '모임' 통장이 있어야 거래내역서를 넣을 수 있어요.")
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
