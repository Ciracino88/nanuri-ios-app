import SwiftUI
import Supabase
import Combine

@MainActor
class SurveyViewModel: ObservableObject {
    @Published var surveys: [Survey] = []
    @Published var isLoading = false

    func fetchSurveys() async {
        isLoading = true
        do {
            var fetched: [Survey] = try await supabase
                .from("surveys")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            fetched = await withTaskGroup(of: Survey.self) { group in
                for survey in fetched {
                    group.addTask {
                        let count: Int = (try? await supabase
                            .from("survey_responses")
                            .select("id", head: true, count: .exact)
                            .eq("survey_id", value: survey.id)
                            .execute()
                            .count) ?? 0
                        var s = survey
                        s.responseCount = count
                        return s
                    }
                }
                var result: [Survey] = []
                for await s in group { result.append(s) }
                return result.sorted { $0.createdAt > $1.createdAt }
            }

            surveys = fetched
        } catch {
            print("설문 로드 실패: \(error)")
        }
        isLoading = false
    }

    func subscribeToRealtime() async {
        let channel = supabase.channel("surveys-realtime")

        let surveyInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "surveys")
        let responseInserts = channel.postgresChange(InsertAction.self, schema: "public", table: "survey_responses")

        await channel.subscribe()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in surveyInserts {
                    await self.fetchSurveys()
                }
            }
            group.addTask {
                for await action in responseInserts {
                    if case .string(let surveyId) = action.record["survey_id"] {
                        await MainActor.run {
                            self.surveys = self.surveys.map { s in
                                guard s.id == surveyId else { return s }
                                var updated = s
                                updated.responseCount += 1
                                return updated
                            }
                        }
                    }
                }
            }
        }
    }

    func subscribeToResponses(surveyId: String, onUpdate: @escaping ([SurveyResponse]) -> Void) async {
        let channel = supabase.channel("survey-responses-\(surveyId)")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "survey_responses")
        await channel.subscribe()

        for await _ in inserts {
            let responses: [SurveyResponse] = (try? await supabase
                .from("survey_responses")
                .select("nickname, answers")
                .eq("survey_id", value: surveyId)
                .execute()
                .value) ?? []
            await MainActor.run { onUpdate(responses) }
        }
    }

    func fetchResults(surveyId: String) async -> (survey: Survey?, responses: [SurveyResponse]) {
        do {
            let survey: Survey = try await supabase
                .from("surveys")
                .select()
                .eq("id", value: surveyId)
                .single()
                .execute()
                .value

            let responses: [SurveyResponse] = try await supabase
                .from("survey_responses")
                .select("nickname, answers")
                .eq("survey_id", value: surveyId)
                .execute()
                .value

            return (survey, responses)
        } catch {
            print("결과 로드 실패: \(error)")
            return (nil, [])
        }
    }
}
