import Foundation

/// 재정 보고서 종류. 탭 진입 시 작성자가 먼저 선택한다.
enum FinanceReportMode: String, CaseIterable, Identifiable {
    case monthly   // 월별 회계 보고서 (전월이월 → 누적 잔액)
    case event     // 행사 결산 내역 (한 행사의 수입·지출 결산)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "월별 회계 보고서"
        case .event: return "행사 결산 내역"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: return "전월이월부터 이어지는 월 단위 장부"
        case .event: return "한 행사의 수입·지출 결산"
        }
    }

    var icon: String {
        switch self {
        case .monthly: return "calendar"
        case .event: return "flag.checkered"
        }
    }
}

/// 장부(통장). 상시 계좌는 월별, 행사 전용 통장은 행사 유형.
struct Ledger: Identifiable, Codable {
    var id: UUID
    let name: String
    let type: String            // "monthly" | "event"
    let createdAt: Date?

    var mode: FinanceReportMode { type == FinanceReportMode.event.rawValue ? .event : .monthly }

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case createdAt = "created_at"
    }
}

struct LedgerInsert: Encodable {
    let name: String
    let type: String
}

struct BankTransaction: Identifiable, Codable {
    var id: UUID
    var ledgerId: UUID?
    let datetime: Date
    let type: String
    let amount: Int
    let balance: Int
    let description: String?
    var category: String?
    var memo: String?
    var receiptUrls: [String]?
    let createdAt: Date?

    var isDeposit: Bool { amount > 0 }
    /// nil 안전 접근용.
    var receipts: [String] { receiptUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, datetime, type, amount, balance, description, category, memo
        case ledgerId = "ledger_id"
        case receiptUrls = "receipt_urls"
        case createdAt = "created_at"
    }
}

struct BankTransactionInsert: Encodable {
    var ledgerId: UUID? = nil
    let datetime: Date
    let type: String
    let amount: Int
    let balance: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, balance, description
        case ledgerId = "ledger_id"
    }
}

/// 거래 편집 저장 시 카테고리·메모·영수증을 한 번에 반영하기 위한 업데이트 페이로드.
struct TransactionEditUpdate: Encodable {
    let category: String?
    let memo: String?
    let receiptUrls: [String]

    enum CodingKeys: String, CodingKey {
        case category, memo
        case receiptUrls = "receipt_urls"
    }
}

/// 거래 분할 항목. 하나의 통장 거래를 여러 회계 항목으로 쪼갤 때 사용.
struct TransactionSplit: Identifiable, Codable {
    var id: UUID
    let transactionId: UUID
    var amount: Int
    var category: String?
    var memo: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, amount, category, memo
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

struct TransactionSplitInsert: Encodable {
    let transactionId: UUID
    let amount: Int
    let category: String?
    let memo: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case amount, category, memo
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

/// 보고서 한 줄을 구성하는 항목. 거래 자체이거나, 분할된 조각이다.
/// (통장 거래와 보고서 항목의 입도 차이를 흡수하는 중간 표현)
struct ReportLineItem {
    let datetime: Date
    let isDeposit: Bool
    let magnitude: Int          // 항상 양수
    let category: String?
    let memo: String?
    let sourceDescription: String?

    /// 묶을 때 쓰는 카테고리 이름. 비어 있으면 **"미분류"** 다.
    ///
    /// 보고서(`FinanceReportExporter`)와 분석 화면(`SpendingDetailView`)이 같은
    /// 이름으로 묶어야 두 곳의 합계가 어긋나지 않는다. 빈 카테고리를 버리지 않고
    /// 한 덩어리로 모으는 것도 그래서다 — 분류가 덜 된 달일수록 그 덩어리가 커야
    /// "아직 안 나눴다" 는 게 보인다.
    var categoryLabel: String {
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return "미분류"
    }
}

/// 카테고리 하나에 묶인 합계. 분석 화면의 막대와 목록이 같이 쓴다.
struct CategoryTotal: Identifiable {
    let name: String
    let amount: Int

    var id: String { name }
}

/// 앱에 보관 중인 원본 거래내역서 PDF
struct StatementFile: Identifiable {
    let url: URL
    let importedAt: Date

    var id: String { url.lastPathComponent }
}
