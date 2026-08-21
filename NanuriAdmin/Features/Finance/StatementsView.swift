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
                            Label("거래내역 불러오기", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .alert("거래내역 불러오기", isPresented: $showReparseResult) {
                    Button("확인") { dismiss() }
                } message: {
                    Text("이 거래내역서를 파싱해 거래내역에 반영했어요.")
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
