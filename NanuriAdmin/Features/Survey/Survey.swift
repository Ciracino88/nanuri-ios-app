import Foundation

struct Survey: Identifiable, Decodable {
    let id: String
    let title: String
    let placeName: String?
    let imageUrl: String?
    let status: String
    let items: [SurveyItem]
    let createdAt: String
    var responseCount: Int = 0

    var isActive: Bool { status == "active" }

    enum CodingKeys: String, CodingKey {
        case id, title, items, status
        case placeName = "place_name"
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }
}

struct SurveyItem: Codable {
    let label: String
    let isStar: Bool
}

struct SurveyResponse: Decodable {
    let nickname: String?
    let answers: [String: SurveyAnswer]
}

enum SurveyAnswer: Decodable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}
