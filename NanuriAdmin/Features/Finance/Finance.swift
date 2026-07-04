import Foundation

struct BankTransaction: Identifiable, Codable {
    var id: UUID
    let datetime: Date
    let type: String
    let amount: Int
    let balance: Int
    let description: String?
    var category: String?
    var memo: String?
    let createdAt: Date?

    var isDeposit: Bool { amount > 0 }

    enum CodingKeys: String, CodingKey {
        case id, datetime, type, amount, balance, description, category, memo
        case createdAt = "created_at"
    }
}

struct BankTransactionInsert: Encodable {
    let datetime: Date
    let type: String
    let amount: Int
    let balance: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, balance, description
    }
}

struct BankTransactionUpdate: Encodable {
    let category: String?
    let memo: String?
}

/// 앱에 보관 중인 원본 거래내역서 PDF
struct StatementFile: Identifiable {
    let url: URL
    let importedAt: Date

    var id: String { url.lastPathComponent }
}

struct FinanceReport: Identifiable, Codable {
    var id: UUID
    let name: String
    let type: String
    let startDate: Date
    let endDate: Date
    var memo: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, type, memo
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }
}
