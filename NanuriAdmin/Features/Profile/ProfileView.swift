import SwiftUI
import Supabase

/// 프로필 탭.
///
/// 헤더에 자리가 없어 갈 곳이 없던 것들이 여기로 모였다 —
/// 아바타 · 프로필 수정 · 로그아웃.
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var profile: ProfileRow?
    @State private var email: String?
    @State private var isLoading = false
    @State private var showProfileEdit = false
    @State private var showLogoutAlert = false

    var body: some View {
        VStack(spacing: 0) {
            AdminHeaderView(title: "프로필")

            if isLoading && profile == nil {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: DS.Spacing.medium) {
                        identityCard
                        if let profile, profile.bankName?.isEmpty == false {
                            accountCard(profile: profile)
                        }
                        actions
                    }
                    .padding(.horizontal, DS.Spacing.screen)
                    .padding(.vertical, DS.Spacing.screen)
                }
                .refreshable { await load() }
            }
        }
        .screenBackground()
        .sheet(isPresented: $showProfileEdit, onDismiss: {
            Task { await load() }
        }) {
            ProfileEditView()
        }
        .alert("로그아웃", isPresented: $showLogoutAlert) {
            Button("로그아웃", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("정말 로그아웃 하시겠어요?")
        }
        .task { await load() }
    }

    // MARK: - 카드

    private var identityCard: some View {
        VStack(spacing: DS.Spacing.medium) {
            AvatarView(url: profile?.avatarUrl, size: DS.Size.avatar)
            VStack(spacing: DS.Spacing.tight) {
                Text(profile?.name ?? "이름 없음")
                    .cardTitle()
                if let email {
                    Text(email)
                        .rowSubtext()
                }
            }
            if let positions = profile?.position, !positions.isEmpty {
                ChipFlowLayout(spacing: DS.Spacing.small) {
                    ForEach(positions, id: \.self) { position in
                        Text(position).tagChip(color: DS.Palette.deposit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: DS.Spacing.section)
    }

    private func accountCard(profile: ProfileRow) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text("내 계좌")
                .rowSubtext()
            Text("\(profile.bankName ?? "") \(profile.accountNumber ?? "")")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "person.crop.circle",
                label: "프로필 수정",
                tint: .primary
            ) {
                showProfileEdit = true
            }
            // 아이콘을 지나 글자 앞에서 시작하게 (좌여백 + 아이콘 + 아이콘~글자 간격)
            Divider().padding(.leading, DS.Spacing.screen + DS.Icon.feature + DS.Spacing.medium)
            actionRow(
                icon: "rectangle.portrait.and.arrow.right",
                label: "로그아웃",
                tint: DS.Palette.withdrawal
            ) {
                showLogoutAlert = true
            }
        }
        .cardStyle(padding: 0)
    }

    private func actionRow(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.feature))
                    .foregroundColor(tint)
                    .frame(width: DS.Icon.feature)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DS.Spacing.screen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 불러오기

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let user = try? await supabase.auth.user() else { return }
        email = user.email
        profile = try? await supabase
            .from("profiles")
            .select()
            .eq("id", value: user.id)
            .single()
            .execute()
            .value as ProfileRow
    }
}
