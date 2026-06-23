import SwiftUI

struct ProfileRow: Decodable {
    let id: UUID
    let name: String
    let accountNumber: String?
    let bankName: String?
    let position: [String]?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case accountNumber = "account_number"
        case bankName = "bank_name"
        case avatarUrl = "avatar_url"
    }
}

struct ProfileUpdate: Encodable {
    let name: String
    let bankName: String
    let accountNumber: String
    let position: [String]
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, position
        case bankName = "bank_name"
        case accountNumber = "account_number"
        case avatarUrl = "avatar_url"
    }
}

let koreanBanks = [
    "국민은행", "신한은행", "우리은행", "하나은행",
    "카카오뱅크", "토스뱅크", "IBK기업은행", "NH농협은행",
    "SC제일은행", "케이뱅크", "새마을금고", "신협", "우체국"
]

let worshipPositions = [
    "인도자", "싱어1", "싱어2", "메인 피아노",
    "세컨 피아노", "어쿠스틱", "베이스", "일렉", "드럼", "PPT"
]
