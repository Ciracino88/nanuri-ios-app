import SwiftUI
import Supabase
import PhotosUI

struct ProfileEditView: View {
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var selectedPositions: Set<String> = []
    @State private var avatarUrl: String?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var avatarData: Data?

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // 타이틀·저장이 있어 시트가 아니라 풀스크린이다 (DESIGN.md §1).
            AdminHeaderView(
                showsNotifications: false,
                center: { Text("프로필 수정").headerTitle() },
                leading: { HeaderBackButton(label: "취소") { dismiss() } },
                trailing: {
                    Button("저장") { Task { await saveProfile() } }
                        .typeStyle(DS.Typo.labelM)
                        .foregroundColor(DS.Ink.brand)
                        .padding(.horizontal, DS.Spacing.small)
                        .disabled(isSaving || name.isEmpty)
                }
            )
            Form {
                // 아바타
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let avatarImage {
                                        avatarImage
                                            .resizable()
                                            .scaledToFill()
                                    } else if let avatarUrl, let url = URL(string: avatarUrl) {
                                        RemoteImage(url: url, maxDimension: DS.Size.avatar) {
                                            defaultAvatarIcon
                                        } failure: {
                                            defaultAvatarIcon
                                        }
                                        .scaledToFill()
                                    } else {
                                        defaultAvatarIcon
                                    }
                                }
                                .frame(width: DS.Size.avatar, height: DS.Size.avatar)
                                .clipShape(Circle())

                                Image(systemName: "camera.circle.fill")
                                    .font(DS.Icon.font(DS.Icon.feature))
                                    .foregroundColor(DS.Ink.brand)
                                    .background(DS.Surface.card.clipShape(Circle()))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

                // 기본 정보
                Section("기본 정보") {
                    HStack {
                        Text("이름").foregroundColor(DS.Ink.secondary)
                        Spacer()
                        TextField("홍길동", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // 포지션
                Section("포지션") {
                    ChipFlowLayout(spacing: 8) {
                        ForEach(worshipPositions, id: \.self) { position in
                            PositionChip(
                                label: position,
                                isSelected: selectedPositions.contains(position)
                            ) {
                                if selectedPositions.contains(position) {
                                    selectedPositions.remove(position)
                                } else {
                                    selectedPositions.insert(position)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                // 계좌 정보
                Section("계좌 정보") {
                    Picker("은행", selection: $bankName) {
                        Text("선택").tag("")
                        ForEach(koreanBanks, id: \.self) { bank in
                            Text(bank).tag(bank)
                        }
                    }
                    HStack {
                        Text("계좌번호").foregroundColor(DS.Ink.secondary)
                        Spacer()
                        TextField("계좌번호 입력", text: $accountNumber)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .typeStyle(DS.Typo.body3)
                            .foregroundColor(DS.Ink.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .screenBackground(DS.Surface.page)
        .task { await loadProfile() }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let item else { return }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        avatarData = data
                        if let uiImage = UIImage(data: data) {
                            avatarImage = Image(uiImage: uiImage)
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.State.scrim.opacity(0.2))
                }
            }
    }

    private var defaultAvatarIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(DS.Ink.disabled)
    }

    func loadProfile() async {
        isLoading = true
        do {
            let user = try await supabase.auth.user()
            let profile: ProfileRow = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            name = profile.name
            bankName = profile.bankName ?? ""
            accountNumber = profile.accountNumber ?? ""
            selectedPositions = Set(profile.position ?? [])
            avatarUrl = profile.avatarUrl
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func saveProfile() async {
        isSaving = true
        error = nil
        do {
            let user = try await supabase.auth.user()
            var finalAvatarUrl = avatarUrl

            if let data = avatarData {
                let path = "\(user.id)/avatar.jpg"
                try await supabase.storage
                    .from("avatars")
                    .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                finalAvatarUrl = try supabase.storage
                    .from("avatars")
                    .getPublicURL(path: path)
                    .absoluteString
            }

            let update = ProfileUpdate(
                name: name,
                bankName: bankName,
                accountNumber: accountNumber,
                position: Array(selectedPositions),
                avatarUrl: finalAvatarUrl
            )
            try await supabase
                .from("profiles")
                .update(update)
                .eq("id", value: user.id)
                .execute()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - 포지션 칩

private struct PositionChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // 글자 크기는 칩이 정한다 — Label 스케일이 컨트롤 전용이다.
            Text(label)
                .selectableChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

