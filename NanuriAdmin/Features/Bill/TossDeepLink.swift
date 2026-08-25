import UIKit
import OSLog

/// 토스 송금 화면을 여는 딥링크.
///
/// **URL 을 만드는 일과 여는 일을 나눴다.** 만드는 쪽(`url(for:)`)은 상태도
/// UIKit 의존도 없는 순수 함수라 단위 테스트로 검증할 수 있고, 여는 쪽(`open(_:)`)
/// 만 `UIApplication` 을 안다. 뷰모델이 URL 문자열을 직접 조립하고 있으면 둘 다 못 한다.
///
/// 토스 딥링크는 **수취인 한 명 · 금액 하나**만 받는다. 그래서 여러 건을 묶는 건
/// 같은 사람일 때뿐이고, 그 판단은 부르는 쪽이 한다 (`ARCHITECTURE.md`).
enum TossDeepLink {

    /// 송금 한 건을 딥링크로 바꾼다. 보낼 수 없는 상태면 `nil`.
    ///
    /// `nil` 이 되는 경우는 셋이다 — 금액이 0 이하이거나, 은행명이 비었거나,
    /// 계좌번호에서 하이픈을 뺀 게 비었을 때.
    static func url(for transfer: TossTransfer) -> URL? {
        url(bankName: transfer.payee.bankName,
            accountNumber: transfer.payee.accountNumber,
            amount: transfer.total)
    }

    static func url(bankName: String, accountNumber: String, amount: Int) -> URL? {
        // 토스는 하이픈 없는 계좌번호를 받는다.
        let digits = accountNumber.replacingOccurrences(of: "-", with: "")
        guard amount > 0, !digits.isEmpty, !bankName.isEmpty else { return nil }

        // 문자열을 직접 이어 붙이지 않는다. 은행명이 한글이라 인코딩이 필요한데,
        // `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` 는
        // `&` 와 `=` 를 **통과시켜서** 값 안에 그런 글자가 있으면 쿼리가 쪼개진다.
        // `URLComponents` 는 값 단위로 올바르게 인코딩한다.
        var components = URLComponents()
        components.scheme = "supertoss"
        components.host = "send"
        components.queryItems = [
            URLQueryItem(name: "bank", value: bankName),
            URLQueryItem(name: "accountNo", value: digits),
            URLQueryItem(name: "amount", value: String(amount)),
        ]
        return components.url
    }

    /// 토스 앱을 연다. 열 수 없으면 로그만 남기고 조용히 돌아간다 —
    /// 여기서 화면에 알림을 띄우지는 않는다. 결과를 묻는 건 돌아온 뒤
    /// `TossResultView` 가 한다.
    @MainActor
    static func open(_ transfer: TossTransfer) {
        guard let url = url(for: transfer) else {
            Log.bill.error("토스 딥링크를 만들지 못했다 — 금액이 0이거나 계좌 정보가 비었다")
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened { Log.bill.error("토스 앱을 열지 못했다") }
        }
    }
}
