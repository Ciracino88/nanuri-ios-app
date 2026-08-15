import SwiftUI

struct AdminHeaderView: View {
    let title: String
    let avatarUrl: String?
    let onRefresh: () -> Void
    let onProfileTap: () -> Void
    /// 계좌부가 있는 화면에서만 넘긴다.
    var onPayeesTap: (() -> Void)? = nil
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showLogoutAlert = false

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    if let onPayeesTap {
                        Button(action: onPayeesTap) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 52, height: 44)
                        }
                        Divider().frame(height: 18)
                    }
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 52, height: 44)
                    }
                    Divider().frame(height: 18)
                    Button {
                        showLogoutAlert = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 52, height: 44)
                    }
                    .alert("로그아웃", isPresented: $showLogoutAlert) {
                        Button("로그아웃", role: .destructive) {
                            Task { await authViewModel.signOut() }
                        }
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("정말 로그아웃 하시겠어요?")
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(Capsule())

                Button(action: onProfileTap) {
                    AvatarView(url: avatarUrl, size: 44)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
