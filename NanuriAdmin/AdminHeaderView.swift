import SwiftUI

struct AdminHeaderView: View {
    let title: String
    let avatarUrl: String?
    let onRefresh: () -> Void
    let onProfileTap: () -> Void
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    Divider().frame(height: 16)
                    Button {
                        Task { await authViewModel.signOut() }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(Capsule())

                Button(action: onProfileTap) {
                    AvatarView(url: avatarUrl, size: 36)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
