import SwiftUI

/// 청구서 탭.
///
/// 평소에는 카드를 눌러 한 건씩 처리하고(`BillDetailView`), 한 사람이 여러 건을
/// 냈을 때는 **묶어 보내기 선택 모드**로 여러 건을 골라 한 번에 보낸다.
/// 토스 딥링크는 수취인 한 명·금액 하나만 받으므로 **같은 사람끼리만** 묶인다.
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
    /// 묶어 보내기 선택 모드. 헤더 왼쪽 버튼으로 켜고 끈다.
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
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
            AdminHeaderView(title: "청구서", leading: {
                HeaderIconButton(
                    systemName: isSelecting ? "xmark" : "checklist",
                    label: isSelecting ? "고르기 그만두기" : "묶어서 보낼 청구서 고르기",
                    tint: isSelecting ? DS.Palette.deposit : .primary
                ) {
                    withAnimation(DS.Motion.control) {
                        if isSelecting { exitSelection() } else { enterSelection() }
                    }
                }
            })

            // 고를 수 있는 건 대기중뿐이라 선택 모드에서는 칩을 걷고 그 자리에
            // 왜 어떤 카드는 못 고르는지를 적는다. 같은 높이라 목록이 안 튄다.
            Group {
                if isSelecting {
                    Text("같은 사람의 대기중 청구서만 함께 보낼 수 있어요")
                        .rowSubtext()
                        .frame(maxWidth: .infinity)
                } else {
                    ChipSelector(items: chipItems, selection: $filter)
                }
            }
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
                            .pullToRefresh { await reload() }
                    } else {
                        List(bills) { bill in
                            BillRowView(bill: bill, selection: isSelecting ? selectionState(for: bill) : nil)
                                .cardRow()
                                .onTapGesture {
                                    if isSelecting {
                                        withAnimation(DS.Motion.control) { toggle(bill) }
                                    } else {
                                        detailBill = bill
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .listStyle(.plain)
                        .screenBackground()
                        .animation(DS.Motion.list, value: bills)
                        // 헤더에 새로고침 버튼이 없다. 목록은 당겨서 새로고침한다
                        // (DESIGN.md 1번). 평소에는 실시간으로 들어온다.
                        .refreshable { await reload() }
                    }
                }
            }

            if isSelecting { selectionBar }
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
                        send([bill], to: payee)
                    }
                    detailBill = nil
                },
                onRegisterPayee: {
                    afterDetail = { payeeEdit = .create(bill.submitterName) }
                    detailBill = nil
                }
            )
            // 높이는 시트가 자기 내용을 재서 정한다 (`BillDetailView.detents`).
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

    private func reload() async {
        await viewModel.fetchBills(showLoading: false)
        await payeeViewModel.fetchPayees(showLoading: false)
    }

    // MARK: - 묶어 보내기

    /// 고른 청구서들. 목록 순서(최근 것이 위)를 그대로 따른다.
    private var selectedBills: [Bill] {
        filteredBills.filter { selection.contains($0.id) }
    }

    private var selectedTotal: Int {
        selectedBills.reduce(0) { $0 + $1.amount }
    }

    /// 지금 고르고 있는 사람. 한 건을 고르면 그 사람 것만 더 고를 수 있다.
    /// 계좌부와 같은 규칙(`normalizedName`)으로 맞춘다.
    private var selectionOwner: String? {
        selectedBills.first?.submitterName.normalizedName
    }

    private func selectionState(for bill: Bill) -> BillRowView.Selection {
        if selection.contains(bill.id) { return .on }
        // 대기중이 아니거나 계좌가 없으면 애초에 보낼 수 없다.
        guard bill.isPending, payeeViewModel.payee(for: bill.submitterName) != nil else { return .blocked }
        guard let owner = selectionOwner else { return .off }
        return bill.submitterName.normalizedName == owner ? .off : .blocked
    }

    private func toggle(_ bill: Bill) {
        guard selectionState(for: bill) != .blocked else { return }
        if selection.contains(bill.id) {
            selection.remove(bill.id)
        } else {
            selection.insert(bill.id)
        }
    }

    private func enterSelection() {
        // 고를 수 있는 건 대기중뿐이다. 다른 칩을 보던 중이면 옮겨 준다.
        filter = .pending
        selection = []
        isSelecting = true
    }

    private func exitSelection() {
        isSelecting = false
        selection = []
    }

    /// 골라 둔 것들을 토스로 넘긴다. 사람은 하나로 정해져 있다.
    private func sendSelected() {
        let bills = selectedBills
        guard let first = bills.first,
              let payee = payeeViewModel.payee(for: first.submitterName) else { return }
        send(bills, to: payee)
        exitSelection()
    }

    /// 토스를 열고, 돌아왔을 때 물어볼 것을 걸어 둔다. 승인은 그 시트가 한다.
    private func send(_ bills: [Bill], to payee: Payee) {
        pendingTransfer = TossTransfer(bills: bills, payee: payee)
        viewModel.openToss(bills: bills, payee: payee)
    }

    /// 목록 아래에 고정되는 선택 요약. 내용이 여기서 잘리므로 위에 선을 긋는다
    /// (DESIGN.md 6번).
    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: DS.Spacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection.isEmpty ? "보낼 청구서를 고르세요" : "\(selectedBills.count)건 선택")
                        .rowTitle()
                    Spacer(minLength: DS.Spacing.small)
                    if !selection.isEmpty {
                        Text("\(selectedTotal.formatted())원")
                            .cardTitle()
                    }
                }
                if !selection.isEmpty {
                    ActionButton(title: "합쳐서 송금하기", kind: .primary, action: sendSelected)
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.top, DS.Spacing.medium)
            .padding(.bottom, DS.Spacing.small)
        }
        .background(Color(.systemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
