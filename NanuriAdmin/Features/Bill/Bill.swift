import Foundation

struct Bill: Identifiable, Decodable, Equatable {
    let id: UUID
    let userId: UUID
    let title: String
    let amount: Int
    let receiptUrl: String
    let status: String
    let createdAt: Date
    let accountNumber: String?
    let bankName: String?
    let submitterName: String?  // 추가
    var userProfile: UserProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case amount
        case receiptUrl = "receipt_url"
        case status
        case createdAt = "created_at"
        case accountNumber = "account_number"
        case bankName = "bank_name"
        case submitterName = "submitter_name"  // 추가
    }
}

struct UserProfile: Decodable, Equatable {
    let name: String
    let accountNumber: String
    let bankName: String

    enum CodingKeys: String, CodingKey {
        case name
        case accountNumber = "account_number"
        case bankName = "bank_name"
    }
}
