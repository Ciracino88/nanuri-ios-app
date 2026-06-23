import SwiftUI

struct SurveyListView: View {
    @StateObject private var viewModel = SurveyViewModel()
    @State private var selectedTab = 0

    var activeSurveys: [Survey] { viewModel.surveys.filter { $0.isActive } }
    var closedSurveys: [Survey] { viewModel.surveys.filter { !$0.isActive } }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
            .navigationTitle("설문 현황")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.fetchSurveys() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
        }
        .task {
            await viewModel.fetchSurveys()
            await viewModel.subscribeToRealtime()
        }
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
