import Foundation

/// 청구자 이름 ↔ 입금 계좌.
///
/// 청구 웹페이지는 공개 URL이라 이름만 받는다. 계좌는 관리자가 여기에 미리
/// 등록해 두고, 들어온 청구서의 이름을 대조해서 찾는다.
struct Payee: Identifiable, Decodable, Equatable {
    let id: UUID
    let name: String
    let bankName: String
    let accountNumber: String
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case id, name, memo
        case bankName = "bank_name"
        case accountNumber = "account_number"
    }

    var accountLine: String {
        "\(bankName) \(accountNumber)".trimmingCharacters(in: .whitespaces)
    }
}

/// INSERT / UPDATE 용 본문.
struct PayeeUpsert: Encodable {
    let name: String
    let bankName: String
    let accountNumber: String
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case name, memo
        case bankName = "bank_name"
        case accountNumber = "account_number"
    }
}

extension String {
    /// 이름 대조용 정규화.
    ///
    /// DB의 `payees_name_normalized_idx` 와 규칙이 반드시 같아야 한다.
    /// 한쪽만 바꾸면 앱에서는 매칭되는데 DB 유니크 제약은 안 걸리는(혹은 반대인)
    /// 상태가 된다.
    var normalizedName: String {
        lowercased().filter { !$0.isWhitespace }
    }

    /// 저장하기 전에 이름의 공백을 다듬는다.
    ///
    /// 스위프트의 `isWhitespace` 와 포스트그레스의 `\s` 가 보는 공백 범위가 미묘하게
    /// 다르다. 특히 비분리 공백(U+00A0)은 앱은 공백으로 보지만 DB는 아니다.
    /// 저장 전에 전부 보통 공백으로 바꿔두면 양쪽 판단이 절대 어긋나지 않는다.
    /// 워커의 `normalizeSpaces` 와 같은 일을 한다.
    var whitespaceNormalized: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
