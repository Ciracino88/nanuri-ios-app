import Foundation

/// 토스뱅크 거래내역서 PDF에서 추출한 텍스트를 거래 목록으로 파싱한다.
/// 상태가 없는 순수 로직 — 텍스트를 넣으면 거래 배열이 나온다 (단위 테스트 용이).
enum TossPdfParser {

    /// 거래 사이에 끼는 표 머리글/발급 정보 등은 description으로 붙이지 않는다.
    private static let footerPrefixes = ["거래일자", "발급일자", "페이지", "토스뱅크", "계좌번호"]

    /// 한 줄 = [날짜][구분][금액][잔액] (그 뒤 description은 줄 끝까지 또는 다음 줄로 이어짐)
    /// 구분값은 특정 단어로 열거하지 않고 "한글/영문 글자 토큰"이면 무엇이든 받는다.
    /// (입금/출금/이자입금 외에 처음 보는 유형도 누락 없이 잡기 위함)
    private static let headerPattern =
        #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+([가-힣A-Za-z]+)\s+(-?[\d,]+)\s+([\d,]+)\s*(.*)$"#

    static func parse(_ text: String) -> [BankTransactionInsert] {
        // 물리적 줄 단위로 처리한다.
        // - 날짜로 시작하는 줄 = 새 거래 (줄 안의 공백은 정당한 공백이므로 보존)
        // - 날짜로 시작하지 않는 줄 = 앞 거래 description의 줄바꿈 연속 → 공백 없이 이어붙임
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let headerRegex = try? NSRegularExpression(pattern: headerPattern) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")

        var result: [BankTransactionInsert] = []
        var pending: (datetime: Date, type: String, amount: Int, balance: Int, desc: String)?

        func flush() {
            guard let p = pending else { return }
            let cleaned = p.desc.trimmingCharacters(in: .whitespaces)
            result.append(BankTransactionInsert(
                datetime: p.datetime,
                type: p.type,
                amount: p.amount,
                balance: p.balance,
                description: cleaned.isEmpty ? nil : cleaned
            ))
            pending = nil
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)

            if let m = headerRegex.firstMatch(in: line, range: range),
               let dtR = Range(m.range(at: 1), in: line),
               let tyR = Range(m.range(at: 2), in: line),
               let amR = Range(m.range(at: 3), in: line),
               let baR = Range(m.range(at: 4), in: line),
               let datetime = formatter.date(from: String(line[dtR])) {
                // 새 거래 시작 → 이전 거래 확정
                flush()

                let amount = Int(String(line[amR]).replacingOccurrences(of: ",", with: "")) ?? 0
                let balance = Int(String(line[baR]).replacingOccurrences(of: ",", with: "")) ?? 0
                var inlineDesc = ""
                if let dR = Range(m.range(at: 5), in: line) {
                    inlineDesc = String(line[dR])
                }
                pending = (datetime, String(line[tyR]), amount, balance, inlineDesc)
            } else if footerPrefixes.contains(where: { line.hasPrefix($0) }) {
                // 표 머리글·발급 정보 등 → 현재 거래를 확정하고 무시
                flush()
            } else if pending != nil {
                // description 줄바꿈 연속 → 공백 없이 이어붙임 (예: "후원" + "금" = "후원금")
                pending!.desc += line
            }
        }
        flush()
        return result
    }
}
