import SwiftUI

private let moodLevels: [(value: Int, label: String, color: Color)] = [
    (1, "불만족", .red),
    (2, "평범", .orange),
    (3, "만족", .green),
]

struct SurveyResultView: View {
    let surveyId: String
    @StateObject private var viewModel = SurveyViewModel()
    @State private var survey: Survey?
    @State private var responses: [SurveyResponse] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let survey {
                List {
                    // 장소 이미지
                    if let imageUrl = survey.imageUrl, let url = URL(string: imageUrl) {
                        Section {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    GeometryReader { geo in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: geo.size.width, height: geo.size.width)
                                            .clipped()
                                            .cornerRadius(12)
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                case .empty:
                                    Color(.systemGray6)
                                        .aspectRatio(1, contentMode: .fit)
                                        .cornerRadius(12)
                                        .overlay(ProgressView())
                                default:
                                    EmptyView()
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    // 요약 정보
                    Section {
                        if let place = survey.placeName, !place.isEmpty {
                            HStack {
                                Label("장소", systemImage: "mappin.and.ellipse")
                                Spacer()
                                Text(place).foregroundColor(.gray)
                            }
                        }
                        HStack {
                            Label("전체 응답자", systemImage: "person.2")
                            Spacer()
                            Text("\(responses.count)명").foregroundColor(.gray)
                        }
                        HStack {
                            Label("설문 항목", systemImage: "list.bullet")
                            Spacer()
                            Text("\(survey.items.count)개").foregroundColor(.gray)
                        }
                        HStack {
                            Label("상태", systemImage: "circle.fill")
                            Spacer()
                            Text(survey.isActive ? "진행 중" : "종료")
                                .foregroundColor(survey.isActive ? .green : .gray)
                        }
                    }

                    if responses.isEmpty {
                        Section {
                            Text("아직 응답이 없습니다")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        ForEach(Array(survey.items.enumerated()), id: \.offset) { index, item in
                            if item.isStar {
                                MoodResultSection(
                                    label: item.label,
                                    index: index,
                                    responses: responses,
                                    total: responses.count
                                )
                            } else {
                                TextResultSection(
                                    label: item.label,
                                    index: index,
                                    responses: responses
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(survey.title)
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .task {
            let result = await viewModel.fetchResults(surveyId: surveyId)
            survey = result.survey
            responses = result.responses
            isLoading = false
            await viewModel.subscribeToResponses(surveyId: surveyId) { newResponses in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    responses = newResponses
                }
            }
        }
    }
}

private struct MoodResultSection: View {
    let label: String
    let index: Int
    let responses: [SurveyResponse]
    let total: Int

    var body: some View {
        Section(label) {
            ForEach(moodLevels, id: \.value) { mood in
                let count = responses.filter {
                    if case .int(let v) = $0.answers[String(index)] { return v == mood.value }
                    return false
                }.count
                let ratio = total > 0 ? Double(count) / Double(total) : 0

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mood.label)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(count)명 (\(Int(ratio * 100))%)")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .contentTransition(.numericText())
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mood.color)
                                .frame(width: geo.size.width * ratio, height: 8)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: ratio)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct TextResultSection: View {
    let label: String
    let index: Int
    let responses: [SurveyResponse]

    struct AnswerEntry: Identifiable {
        let id = UUID()
        let text: String
        let nickname: String?
    }

    var answers: [AnswerEntry] {
        responses.compactMap {
            if case .string(let s) = $0.answers[String(index)], !s.trimmingCharacters(in: .whitespaces).isEmpty {
                return AnswerEntry(text: s, nickname: $0.nickname)
            }
            return nil
        }
    }

    var body: some View {
        if !answers.isEmpty {
            Section(label) {
                ForEach(answers) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text)
                            .font(.subheadline)
                        if let nick = entry.nickname, !nick.isEmpty {
                            Text(nick)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
