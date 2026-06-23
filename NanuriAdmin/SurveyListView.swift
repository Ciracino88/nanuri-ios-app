import SwiftUI

struct SurveyListView: View {
    @StateObject private var viewModel = SurveyViewModel()
    @State private var selectedTab = 0
    @State private var avatarUrl: String?
    @State private var showProfileEdit = false

    var activeSurveys: [Survey] { viewModel.surveys.filter { $0.isActive } }
    var closedSurveys: [Survey] { viewModel.surveys.filter { !$0.isActive } }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AdminHeaderView(
                    title: "설문 현황",
                    avatarUrl: avatarUrl,
                    onRefresh: { Task { await viewModel.fetchSurveys() } },
                    onProfileTap: { showProfileEdit = true }
                )

                PillPicker(
                    tabs: [
                        ("진행 중", activeSurveys.count),
                        ("종료", closedSurveys.count)
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
                        let surveys = selectedTab == 0 ? activeSurveys : closedSurveys
                        if surveys.isEmpty {
                            Spacer()
                            Text(selectedTab == 0 ? "진행 중인 설문이 없어요" : "종료된 설문이 없어요")
                                .foregroundColor(.gray)
                            Spacer()
                        } else {
                            List(surveys) { survey in
                                NavigationLink(destination: SurveyResultView(surveyId: survey.id)) {
                                    SurveyRowView(survey: survey)
                                }
                            }
                            .listStyle(.insetGrouped)
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
        .task {
            await viewModel.fetchSurveys()
            await loadAvatar()
            await viewModel.subscribeToRealtime()
        }
    }

    private func loadAvatar() async {
        guard let user = try? await supabase.auth.user() else { return }
        struct AvatarRow: Decodable {
            let avatarUrl: String?
            enum CodingKeys: String, CodingKey { case avatarUrl = "avatar_url" }
        }
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

private struct SurveyRowView: View {
    let survey: Survey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(survey.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(survey.isActive ? "진행 중" : "종료")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(survey.isActive ? .green : .gray)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((survey.isActive ? Color.green : Color.gray).opacity(0.12))
                    .cornerRadius(6)
            }
            if let place = survey.placeName, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            HStack(spacing: 12) {
                Label("\(survey.items.count)개 항목", systemImage: "list.bullet")
                Label("\(survey.responseCount)명 참여", systemImage: "person.2")
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}
