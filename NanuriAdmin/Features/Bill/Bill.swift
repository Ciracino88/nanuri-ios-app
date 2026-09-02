import Foundation
import SwiftUI

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
    /// 상태를 바꾼 순간. 트리거(`touch_bill_processed_at`)가 `now()` 로 찍는다.
    ///
    /// **묶어 보내기로 같이 승인한 청구들은 이 값이 한 마이크로초까지 같다** —
    /// `updateStatus(billIds:)` 가 한 요청에 처리하므로 `now()` 가 한 번만 불린다.
    /// 그래서 이 값이 곧 **토스 송금 한 건**을 가리키는 열쇠다
    /// (`StatementMatcher`). 대기중이면 `nil`.
    let processedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, amount, status
        case submitterName = "submitter_name"
        case receiptUrl = "receipt_url"
        case createdAt = "created_at"
        case processedAt = "processed_at"
    }
}

// MARK: - 상태

/// 상태 하나를 카드와 상세 시트가 같이 쓴다. 두 곳에 따로 적으면 색이 갈라진다.
extension Bill {
    /// 아직 처리하지 않은 청구서. 송금·거절은 이때만 할 수 있다.
    var isPending: Bool { status == "pending" }

    var statusLabel: String {
        switch status {
        case "approved": return "송금완료"
        case "rejected": return "거절"
        default: return "대기중"
        }
    }

    /// 상세 시트 머리에서 금액 바로 아래 적는 한 줄. **칩(`statusLabel`)과 같은 값을
    /// 문장으로 적은 것이다.** 시트에는 칩을 두지 않는다 — 한 건만 들여다보는
    /// 자리라 "지금 어떤 상태인가"를 배지로 줄여 쓸 이유가 없다.
    var statusSentence: String {
        switch status {
        case "approved": return "송금을 완료했어요"
        case "rejected": return "거절한 청구서예요"
        default: return "아직 송금하지 않았어요"
        }
    }

    /// 상태 배지의 색 쌍 (글자색 + 옅은 바탕).
    ///
    /// 거절이 `danger` 다 — 출금색(`withdrawal`)이 아니다. 이 시스템에서 출금은
    /// 검정이고 빨강은 되돌릴 수 없는 것에만 남는다 (`DS.Palette` 참고).
    var statusTone: DS.ColorTone {
        switch status {
        case "approved": return DS.Tone.done
        case "rejected": return DS.Tone.danger
        default: return DS.Tone.pending
        }
    }

    /// 글자·아이콘만 필요한 자리 (상세 시트의 상태 줄).
    var statusColor: Color { statusTone.content }
}

// MARK: - 목록 거르개

/// 청구서 탭 위의 칩 넷. `allCases` 순서가 곧 칩 순서다.
/// 상태 문자열(`rawValue`)은 여기서만 다룬다.
enum BillFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case approved
    case rejected

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "대기중"
        case .approved: return "완료"
        case .rejected: return "거절"
        case .all: return "전체"
        }
    }

    func matches(_ bill: Bill) -> Bool {
        self == .all || bill.status == rawValue
    }
}
