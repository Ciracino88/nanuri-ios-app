import SwiftUI

private struct AvatarRow: Decodable {
    let avatarUrl: String?
    enum CodingKeys: String, CodingKey {
        case avatarUrl = "avatar_url"
    }
}

struct BillListView: View {
    @StateObject private var viewModel = BillViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showProfileEdit = false
    @State private var pendingBill: Bill? = nil
    @State private var showConfirmSheet = false
    @State private var selectedTab = 0
    @State private var avatarUrl: String?
    @Environment(\.scenePhase) var scenePhase

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
        ZStack {
            NavigationView {
                VStack(spacing: 0) {
                    // 커스텀 헤더
                    HStack(alignment: .center) {
                        Text("청구서 목록")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        HStack(spacing: 8) {
                            HStack(spacing: 0) {
                                Button {
                                    Task { await viewModel.fetchBills() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 36, height: 36)
                                }
                                Divider().frame(height: 16)
                                Menu {
                                    Button("프로필 수정") { showProfileEdit = true }
                                    Button("로그아웃", role: .destructive) {
                                        Task { await authViewModel.signOut() }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 36, height: 36)
                                }
                            }
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())

                            Button { showProfileEdit = true } label: {
                                AvatarView(url: avatarUrl, size: 36)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

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
                                    BillRowView(bill: bill, viewModel: viewModel, pendingBill: $pendingBill)
                                        .listRowInsets(EdgeInsets())
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                                .listStyle(.plain)
                                .background(Color(.systemGroupedBackground))
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
            }

            if let bill = pendingBill, showConfirmSheet {
                TossResultView(
                    bill: bill,
                    onApprove: {
                        Task {
                            await viewModel.updateStatus(billId: bill.id, status: "approved")
                            pendingBill = nil
                            showConfirmSheet = false
                        }
                    },
                    onCancel: {
                        pendingBill = nil
                        showConfirmSheet = false
                    }
                )
            }
        }
        .task {
            await viewModel.fetchBills()
            await loadAvatar()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active && pendingBill != nil {
                showConfirmSheet = true
            }
        }
    }

    private func loadAvatar() async {
        guard let user = try? await supabase.auth.user() else { return }
        let row = try? await supabase
            .from("user_profiles")
            .select("avatar_url")
            .eq("id", value: user.id)
            .single()
            .execute()
            .value as AvatarRow
        avatarUrl = row?.avatarUrl
    }
}

// MARK: - 공용 아바타 뷰

struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        defaultIcon
                    }
                }
            } else {
                defaultIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var defaultIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(Color(.systemGray3))
    }
}
