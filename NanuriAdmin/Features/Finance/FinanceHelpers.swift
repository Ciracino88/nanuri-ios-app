import SwiftUI

/// 칩들이 줄 끝에서 자동으로 다음 줄로 넘어가는 간단한 흐름 레이아웃.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 재정 탭 진입 시 어느 장부(통장)를 열지 고르는 게이트 화면.
struct FinanceLedgerGateView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showNewLedger = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.ledgers.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 46))
                            .foregroundColor(.secondary)
                        Text("장부가 없어요")
                            .font(.headline)
                        Text("통장별로 장부를 만들어 관리해요.\n상시 계좌는 '월별 회계', 행사 통장은 '행사 결산'.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showNewLedger = true
                        } label: {
                            Label("새 장부 만들기", systemImage: "plus")
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.ledgers) { ledger in
                            Button {
                                Task { await viewModel.selectLedger(ledger) }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: ledger.mode.icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(.blue)
                                        .frame(width: 42, height: 42)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ledger.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(ledger.mode.title)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            indexSet.map { viewModel.ledgers[$0] }.forEach { ledger in
                                Task { await viewModel.deleteLedger(ledger) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("재정 관리")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewLedger = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showNewLedger) {
                NewLedgerView(viewModel: viewModel)
            }
        }
        .task { await viewModel.fetchLedgers() }
    }
}

/// 새 장부 생성 (이름 + 유형).
struct NewLedgerView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var mode: FinanceReportMode = .monthly
    @State private var creating = false

    var body: some View {
        NavigationView {
            Form {
                Section("장부 이름") {
                    TextField("예: 나누리 상시, 2024 체육대회", text: $name)
                }
                Section("유형") {
                    Picker("유형", selection: $mode) {
                        Text("월별 회계").tag(FinanceReportMode.monthly)
                        Text("행사 결산").tag(FinanceReportMode.event)
                    }
                    .pickerStyle(.segmented)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("새 장부")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("만들기") {
                        Task {
                            creating = true
                            if let ledger = await viewModel.createLedger(name: name, mode: mode) {
                                dismiss()
                                await viewModel.selectLedger(ledger)
                            }
                            creating = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                }
            }
        }
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
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
}

/// 내보낼 파일을 sheet(item:)에 넘기기 위한 래퍼.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController(공유시트) 래퍼. 파일 앱 저장·메일·메신저 공유 등을 지원.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
