import SwiftUI
import Supabase

private struct AvatarRow: Decodable {
    let avatarUrl: String?
    enum CodingKeys: String, CodingKey {
        case avatarUrl = "avatar_url"
    }
}

/// 계좌부 시트를 띄우는 트리거. name이 있으면 그 이름으로 등록 화면을 미리 연다.
struct PayeeSheet: Identifiable {
    let name: String?
    var id: String { name ?? "__all__" }
}

struct BillListView: View {
    @StateObject private var viewModel = BillViewModel()
    @StateObject private var payeeViewModel = PayeeViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showProfileEdit = false
    @State private var pendingBill: Bill? = nil
    @State private var selectedTab = 0
    @State private var avatarUrl: String?
    /// 계좌부 시트. 미등록 청구서에서 넘어오면 이름이 담긴다.
    @State private var payeeSheet: PayeeSheet?

    var pendingBills: [Bill] {
        viewModel.bills
            .filter { $0.status == "pending" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var processedBills: [Bill] {
        viewModel.bills
            .filter { $0.status != "pending" }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationView {
                VStack(spacing: 0) {
                    AdminHeaderView(
                        title: "청구서 목록",
                        avatarUrl: avatarUrl,
                        onRefresh: {
                            Task {
                                await viewModel.fetchBills()
                                await payeeViewModel.fetchPayees(showLoading: false)
                            }
                        },
                        onProfileTap: { showProfileEdit = true },
                        onPayeesTap: { payeeSheet = PayeeSheet(name: nil) }
                    )

                    PillPicker(
                        tabs: [
                            ("처리 대기", pendingBills.count),
                            ("처리 완료", processedBills.count)
                        ],
                        selection: $selectedTab
                    )
                    .padding()

                    Group {
                        if viewModel.isLoading {
                            Spacer()
                            ProgressView()
                            Spacer()
                        } else {
                            let bills = selectedTab == 0 ? pendingBills : processedBills
                            if bills.isEmpty {
                                Spacer()
                                Text(selectedTab == 0 ? "대기 중인 청구서가 없어요" : "처리된 청구서가 없어요")
                                    .foregroundColor(.gray)
                                Spacer()
                            } else {
                                List(bills) { bill in
                                    BillRowView(
                                        bill: bill,
                                        payee: payeeViewModel.payee(for: bill.submitterName),
                                        viewModel: viewModel,
                                        pendingBill: $pendingBill,
                                        onRegisterPayee: { name in payeeSheet = PayeeSheet(name: name) }
                                    )
                                        .listRowInsets(EdgeInsets())
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity
                                        ))
                                }
                                .listStyle(.plain)
                                .background(Color(.systemGroupedBackground))
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: bills)
                            }
                        }
                    }
                }
                .navigationBarHidden(true)
                .sheet(isPresented: $showProfileEdit, onDismiss: {
                    Task { await loadAvatar() }
                }) {
                    ProfileEditView()
                }
                .sheet(item: $payeeSheet) { sheet in
                    PayeeListView(viewModel: payeeViewModel, prefilledName: sheet.name)
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
        }
        .task {
            await viewModel.fetchBills()
            await payeeViewModel.fetchPayees()
            await loadAvatar()
            await viewModel.subscribeToRealtime()
        }
    }

    private func loadAvatar() async {
        guard let user = try? await supabase.auth.user() else { return }
        let row = try? await supabase
            .from("profiles")
            .select("avatar_url")
            .eq("id", value: user.id)
            .single()
            .execute()
            .value as AvatarRow
        avatarUrl = row?.avatarUrl
    }
}

