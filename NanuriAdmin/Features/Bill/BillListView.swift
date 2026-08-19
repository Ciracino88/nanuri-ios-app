import SwiftUI

struct BillListView: View {
    @StateObject private var viewModel = BillViewModel()
    /// 계좌부 탭과 같은 인스턴스. ContentView 가 갖고 있다.
    @ObservedObject var payeeViewModel: PayeeViewModel
    /// 토스에 다녀온 뒤 결과를 물을 송금. 묶어서 보내면 청구서가 여럿 들어 있다.
    @State private var pendingTransfer: TossTransfer?
    /// 처음 여는 자리는 **대기중**이다. 전체가 아니라 할 일이 먼저다.
    @State private var filter: BillFilter = .pending
    /// 계좌 미등록 청구서에서 바로 띄우는 등록 시트. 목록을 거치지 않는다.
    @State private var payeeEdit: PayeeEditTarget?
    /// 카드를 누르면 열리는 상세 시트. 청구서로 하는 일은 전부 여기서 한다.
    @State private var detailBill: Bill?
    /// 상세 시트가 닫힌 **뒤에** 열 시트. 시트 위에 시트를 겹치지 않으려고 한 박자 미룬다.
    @State private var afterDetail: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase

    /// 지금 칩으로 거른 목록. 최근 것이 위로 온다.
    var filteredBills: [Bill] {
        viewModel.bills
            .filter { filter.matches($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "아직 들어온 청구서가 없어요"
        case .pending: return "대기 중인 청구서가 없어요"
        case .approved: return "송금 완료된 청구서가 없어요"
        case .rejected: return "거절한 청구서가 없어요"
        }
    }

    private var chipItems: [ChipSelector<BillFilter>.Item] {
        BillFilter.allCases.map { option in
            .init(
                value: option,
                label: option.label,
                count: viewModel.bills.filter { option.matches($0) }.count
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminHeaderView(title: "청구서") {
                Task {
                    await viewModel.fetchBills()
                    await payeeViewModel.fetchPayees(showLoading: false)
                }
            }

            ChipSelector(items: chipItems, selection: $filter)
                .padding(.vertical, DS.Spacing.medium)

            Group {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    let bills = filteredBills
                    if bills.isEmpty {
                        EmptyStateView(title: emptyTitle)
                    } else {
                        List(bills) { bill in
                            BillRowView(bill: bill)
                                .cardRow()
                                .onTapGesture { detailBill = bill }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .listStyle(.plain)
                        .screenBackground()
                        .animation(DS.Motion.list, value: bills)
                    }
                }
            }
        }
        .screenBackground()
        .sheet(item: $detailBill, onDismiss: {
            // 상세 시트가 완전히 닫힌 뒤에 다음 시트를 연다. 같은 순간에 둘을
            // 겹치면 SwiftUI 가 뒤엣것을 조용히 삼킨다.
            afterDetail?()
            afterDetail = nil
        }) { bill in
            BillDetailView(
                bill: bill,
                payee: payeeViewModel.payee(for: bill.submitterName),
                siblings: viewModel.pendingSiblings(of: bill),
                viewModel: viewModel,
                onTransfer: { bills in
                    afterDetail = {
                        guard let payee = payeeViewModel.payee(for: bill.submitterName) else { return }
                        pendingTransfer = TossTransfer(bills: bills, payee: payee)
                        viewModel.openToss(bills: bills, payee: payee)
                    }
                    detailBill = nil
                },
                onRegisterPayee: {
                    afterDetail = { payeeEdit = .create(bill.submitterName) }
                    detailBill = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $payeeEdit) { target in
            PayeeEditView(viewModel: payeeViewModel, target: target)
        }
        .sheet(item: $pendingTransfer) { transfer in
            TossResultView(
                transfer: transfer,
                onApprove: {
                    Task {
                        // 묶은 건 전부 한 번에 완료로 넘긴다. 토스에서 한 번 보냈으므로
                        // 하나만 완료로 남으면 나머지가 다시 청구된 것처럼 보인다.
                        await viewModel.updateStatus(billIds: transfer.billIds, status: "approved")
                        pendingTransfer = nil
                    }
                },
                onCancel: {
                    pendingTransfer = nil
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
        }
        .task {
            // 구독은 뷰모델이 들고 있어서 여기서 부르는 건 처음 한 번뿐이다.
            // 탭을 오갈 때마다 다시 붙이면 SDK 가 죽은 채널을 돌려준다
            // (`BillViewModel.subscribeToRealtime`).
            viewModel.subscribeToRealtime()
            await viewModel.fetchBills()
            await payeeViewModel.fetchPayees()
        }
        // 백그라운드에 있는 동안 웹소켓이 끊기면 그 사이 변경은 못 받는다.
        // 돌아올 때 한 번 맞춰 주는 안전망이다.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.fetchBills(showLoading: false) }
        }
    }
}
