import SwiftUI

struct AdminHeaderView: View {
    let title: String
    let avatarUrl: String?
    let onRefresh: () -> Void
    let onProfileTap: () -> Void
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
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: DS.Icon.action, weight: .medium))
                            .frame(width: 52, height: DS.Size.avatar)
                    }
                    Divider().frame(height: 18)
                    Button {
                        showLogoutAlert = true
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: DS.Icon.action, weight: .medium))
                            .foregroundColor(DS.Palette.withdrawal)
                            .frame(width: 52, height: DS.Size.avatar)
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
                    AvatarView(url: avatarUrl, size: DS.Size.avatar)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
