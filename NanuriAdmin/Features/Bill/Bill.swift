import Foundation

/// 카카오 챗봇으로 접수된 청구서.
/// 청구자의 이름·은행·계좌는 청구 시점 값이 행에 박제되어 있어 조인이 필요 없다.
struct Bill: Identifiable, Decodable, Equatable {
    let id: UUID
    let title: String
    let amount: Int
    let submitterName: String
    let bankName: String
    let accountNumber: String
    let receiptUrl: String?
    let note: String?
    let status: String
    let createdAt: Date

    var hasReceipt: Bool { !(receiptUrl ?? "").isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, title, amount, status, note
        case submitterName = "submitter_name"
        case bankName = "bank_name"
        case accountNumber = "account_number"
        case receiptUrl = "receipt_url"
        case createdAt = "created_at"
    }
}
