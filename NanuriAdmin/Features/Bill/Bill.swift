import Foundation

/// 공개 청구 웹페이지로 접수된 청구서.
///
/// 폼이 받는 값은 이름·항목·금액·영수증 네 가지뿐이다.
/// 송금 계좌는 이름으로 계좌부(`Payee`)를 대조해서 찾는다.
struct Bill: Identifiable, Decodable, Equatable {
    let id: UUID
    let title: String
    let amount: Int
    let submitterName: String
    let receiptUrl: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, amount, status
        case submitterName = "submitter_name"
        case receiptUrl = "receipt_url"
        case createdAt = "created_at"
    }
}
