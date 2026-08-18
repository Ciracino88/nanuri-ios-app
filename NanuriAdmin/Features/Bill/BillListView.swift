import SwiftUI

struct BillListView: View {
    @StateObject private var viewModel = BillViewModel()
    /// 계좌부 탭과 같은 인스턴스. ContentView 가 갖고 있다.
    @ObservedObject var payeeViewModel: PayeeViewModel
    @State private var pendingBill: Bill? = nil
    /// 처음 여는 자리는 **대기중**이다. 전체가 아니라 할 일이 먼저다.
    @State private var filter: BillFilter = .pending
    /// 계좌 미등록 청구서에서 바로 띄우는 등록 시트. 목록을 거치지 않는다.
    @State private var payeeEdit: PayeeEditTarget?
    /// 카드를 누르면 열리는 상세 시트. 청구서로 하는 일은 전부 여기서 한다.
    @State private var detailBill: Bill?
    /// 상세 시트가 닫힌 **뒤에** 열 시트. 시트 위에 시트를 겹치지 않으려고 한 박자 미룬다.
    @State private var afterDetail: (() -> Void)?

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
                viewModel: viewModel,
                onTransfer: {
                    afterDetail = {
                        guard let payee = payeeViewModel.payee(for: bill.submitterName) else { return }
                        pendingBill = bill
                        viewModel.openToss(bill: bill, payee: payee)
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
        .sheet(item: $pendingBill) { bill in
            TossResultView(
                bill: bill,
                payee: payeeViewModel.payee(for: bill.submitterName),
                onApprove: {
                    Task {
                        await viewModel.updateStatus(billId: bill.id, status: "approved")
                        pendingBill = nil
                    }
                },
                onCancel: {
                    pendingBill = nil
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
        }
        .task {
            await viewModel.fetchBills()
            await payeeViewModel.fetchPayees()
            await viewModel.subscribeToRealtime()
        }
    }
}
