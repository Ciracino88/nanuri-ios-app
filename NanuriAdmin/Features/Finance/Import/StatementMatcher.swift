import Foundation

/// 같은 순간에 승인된 청구 묶음. **이것이 토스 송금 한 건이다.**
///
/// 묶어 보내기가 `updateStatus(billIds:)` 로 **한 요청에** 승인하고 트리거가
/// `now()` 를 찍으므로, 같이 승인된 청구들의 `processed_at` 은 한 마이크로초까지
/// 같다. 그 묶음의 합계가 곧 토스에서 빠져나간 금액이다.
struct BillGroup: Identifiable {
    let processedAt: Date
    let submitterName: String
    let bills: [Bill]

    var id: String { "\(processedAt.timeIntervalSince1970)|\(submitterName)" }
    var total: Int { bills.reduce(0) { $0 + $1.amount } }

    /// 장부에 적을 줄들. **같은 제목은 한 줄로 합친다.**
    ///
    /// 사용자가 손으로 하던 방식 그대로다 — 이승호 458,000 은 청구 4건(수영장
    /// 260,000 · 카페모임 110,500 · 파라솔 60,000 · 카페모임 27,500)인데 장부에는
    /// 3줄(카페모임 138,000)로 적혔다. 박영훈 야식 124,300 + 19,280 도 한 줄이다.
    ///
    /// 처음 나온 순서를 지킨다. 금액순으로 다시 세우면 사람이 적은 흐름이 흐트러진다.
    var ledgerLines: [(title: String, amount: Int)] {
        ledgerLinesWithReceipts.map { ($0.title, $0.amount) }
    }

    /// 장부 줄 + **그 줄에 딸린 영수증들.** 영수증이 항목별로 붙으므로 제목묶음마다
    /// 그 제목 청구들의 영수증을 모은다(중복 제거, 나온 순서 유지).
    var ledgerLinesWithReceipts: [(title: String, amount: Int, receiptUrls: [String])] {
        var order: [String] = []
        var sums: [String: Int] = [:]
        var receipts: [String: [String]] = [:]
        var seen: [String: Set<String>] = [:]
        for bill in bills {
            let title = bill.title.trimmingCharacters(in: .whitespaces)
            if sums[title] == nil { order.append(title); receipts[title] = []; seen[title] = [] }
            sums[title, default: 0] += bill.amount
            let url = bill.receiptUrl.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty, seen[title]?.insert(url).inserted == true {
                receipts[title, default: []].append(url)
            }
        }
        return order.map { ($0, sums[$0] ?? 0, receipts[$0] ?? []) }
    }
}

/// 거래내역서 한 줄과, 그것에 맞을 법한 청구 묶음들.
struct StatementMatch: Identifiable {
    let line: ParsedStatementLine
    /// **이미 장부에 있는 줄인가.** 같은 내역서를 두 번 불러와도 중복이 안 생기게 한다.
    ///
    /// 예전에는 `unique (ledger_id, datetime, amount)` 가 DB 에서 막았는데, 그 제약은
    /// 수기 입력에서 같은 날 같은 금액 거래 둘을 막아 버려서 걷어냈다. 그 일을
    /// **불러오기 경로에서만** 여기서 대신한다 — 손으로 넣는 쪽은 계속 자유롭다.
    let alreadyImported: Bool
    /// 순위순. 앞이 가장 그럴듯하다.
    let candidates: [BillGroup]
    /// 사람이 고른(또는 자동으로 정해진) 묶음. 비어 있으면 청구 없이 그냥 넣는다.
    var chosenId: String?

    /// **통장 사이 이체로 보이는 줄인가.** 적요가 다른 통장의 `holderName` 과
    /// 같으면 켜진다. 사람이 끌 수 있다 — 이름이 우연히 같을 수 있고, 그때
    /// 잠가 두면 빠져나갈 길이 없다. (통장이 둘뿐이라 상대는 늘 '다른 통장 하나'다.)
    var isInternalTransfer: Bool

    /// 사람이 적은 적요. **비어 있으면 은행 적요 그대로 들어간다.**
    ///
    /// 적으면 조각 하나짜리 분할이 된다 — 거래의 적요(은행 값)를 덮어쓰지 않는다.
    /// 청구 묶음을 골랐으면 그 제목들이 적요라 이 칸은 안 쓴다.
    var manualDescription: String = ""
    /// 사람이 적은 카테고리. 이 줄에서 생기는 **모든 조각**에 같이 붙는다.
    var manualCategory: String = ""

    var id: String { "\(line.datetime.timeIntervalSince1970)|\(line.amount)" }
    var chosen: BillGroup? { candidates.first { $0.id == chosenId } }

    /// 이 줄이 **미리보기**에 보여줄 장부 조각들. 내부 이체나 "청구 없이 그냥 넣기"는
    /// 따로 보여줄 조각이 없어 빈 배열이다(저장은 `itemSpecs` 가 통짜 항목을 만든다).
    var ledgerLines: [(title: String, amount: Int)] {
        if isInternalTransfer { return [] }
        if let group = chosen { return group.ledgerLines }
        let d = manualDescription.trimmingCharacters(in: .whitespaces)
        let c = manualCategory.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty || !c.isEmpty else { return [] }
        return [(d.isEmpty ? (line.description ?? "") : d, abs(line.amount))]
    }

    /// 이 거래가 장부에 만들 **항목들.** 저장이 이걸 그대로 넣는다 — 모든 거래는
    /// 최소 한 항목으로 완전히 풀려야 은행 증명(거래)과 장부(항목)가 대조된다.
    /// - Parameter txAmount: 부호가 여기서 나온다. 청구 조각도 이 부호를 따른다.
    func itemSpecs(txAmount: Int) -> [ItemSpec] {
        if isInternalTransfer {
            return [ItemSpec(amount: txAmount, category: nil, description: nil,
                             receiptUrls: [], isInternalTransfer: true)]
        }
        let c = manualCategory.trimmingCharacters(in: .whitespaces)
        let category: String? = c.isEmpty ? nil : c
        if let group = chosen {
            let sign = txAmount < 0 ? -1 : 1
            return group.ledgerLinesWithReceipts.map { line in
                ItemSpec(amount: sign * line.amount, category: category,
                         description: line.title, receiptUrls: line.receiptUrls,
                         isInternalTransfer: false)
            }
        }
        let d = manualDescription.trimmingCharacters(in: .whitespaces)
        if !d.isEmpty || category != nil {
            return [ItemSpec(amount: txAmount, category: category,
                             description: d.isEmpty ? nil : d, receiptUrls: [],
                             isInternalTransfer: false)]
        }
        // 아무 것도 없으면 통짜 항목 하나. 적요는 은행 값으로 떨어지게 nil 로 둔다.
        return [ItemSpec(amount: txAmount, category: nil, description: nil,
                         receiptUrls: [], isInternalTransfer: false)]
    }
}

/// 거래 하나가 만들 항목 하나의 명세. 화면과 저장이 같은 답을 쓰도록 한 벌만 둔다.
struct ItemSpec {
    let amount: Int              // 부호 붙은 금액
    let category: String?
    let description: String?
    let receiptUrls: [String]
    let isInternalTransfer: Bool
}

/// 거래내역서와 청구서를 맞춘다.
///
/// **상태도 네트워크도 없는 순수 로직이다.** 넣으면 나온다 — 화면과 뷰모델은
/// 결과를 쓰기만 한다.
enum StatementMatcher {

    /// 승인된 청구를 `processed_at` + 이름으로 묶는다.
    static func groups(from bills: [Bill]) -> [BillGroup] {
        var buckets: [String: [Bill]] = [:]
        for bill in bills where bill.status == "approved" {
            guard let at = bill.processedAt else { continue }
            let key = "\(at.timeIntervalSince1970)|\(bill.submitterName.normalizedName)"
            buckets[key, default: []].append(bill)
        }
        return buckets.values.compactMap { group -> BillGroup? in
            guard let first = group.first, let at = first.processedAt else { return nil }
            return BillGroup(processedAt: at,
                             submitterName: first.submitterName,
                             bills: group.sorted { $0.amount > $1.amount })
        }
        .sorted { $0.processedAt < $1.processedAt }
    }

    /// 내역서 줄마다 후보를 찾고, 확실한 것만 미리 골라 둔다.
    ///
    /// **금액이 1차 키다.** 시각은 순위를 매기는 데만 쓴다 — 송금 건은 승인이
    /// 8~38초 뒤라 잘 맞지만 **체크카드결제는 26~27시간까지 벌어진다**(현장에서
    /// 긁고 승인은 나중). 이름도 보조일 뿐이다. 체크카드는 토스 적요가 예금주가
    /// 아니라 가맹점 이름(`우성볼링장`·`도래샘`)이라 아예 안 맞는다.
    ///
    /// ⚠️ **시각을 시간대 변환하지 말 것.** `Bill.processedAt` 도 `line.datetime` 도
    /// 절대 시각(`Date`)이라 그대로 빼면 된다. 대시보드에서 `to_char` 로 보면 UTC 라
    /// 9시간 어긋나 보이는데, 그건 **찍어 보는 방식의 문제**지 값의 문제가 아니다.
    /// 여기에 9시간을 더하면 오히려 전부 틀어진다.
    /// - Parameter accounts: 내부 이체 판정에 쓴다. `holderName` 이 있는 통장만
    ///   의미가 있다 — 적요가 그 이름이면 그 통장과 주고받은 것이다.
    static func matches(lines: [ParsedStatementLine],
                        groups: [BillGroup],
                        existing: [BankTransaction],
                        accounts: [Account] = []) -> [StatementMatch] {

        // 적요에 찍히는 예금주명 → 통장. 이름이 없는 통장은 판정에 못 쓴다.
        var accountByAlias: [String: UUID] = [:]
        for account in accounts {
            let alias = (account.holderName ?? "").normalizedName
            guard !alias.isEmpty else { continue }
            accountByAlias[alias] = account.id
        }

        // 어느 묶음이 몇 줄에서 후보로 걸리는지 — 자동 선택을 판단하는 데 쓴다.
        var candidatesByLine: [[BillGroup]] = []

        for line in lines {
            // 내부 이체에는 맞을 청구가 없다. 금액이 우연히 청구 묶음과 같을 수
            // 있으므로 **후보를 아예 만들지 않는다.**
            guard accountByAlias[(line.description ?? "").normalizedName] == nil else {
                candidatesByLine.append([])
                continue
            }
            // 청구는 나가는 돈이다. 입금·이자에는 맞을 청구가 없다.
            guard line.amount < 0 else {
                candidatesByLine.append([])
                continue
            }
            let magnitude = abs(line.amount)
            let nameKey = (line.description ?? "").normalizedName

            let found = groups
                .filter { $0.total == magnitude }
                .sorted { a, b in
                    let aName = a.submitterName.normalizedName == nameKey
                    let bName = b.submitterName.normalizedName == nameKey
                    if aName != bName { return aName }   // 이름이 맞으면 먼저
                    return abs(a.processedAt.timeIntervalSince(line.datetime))
                         < abs(b.processedAt.timeIntervalSince(line.datetime))
                }
            candidatesByLine.append(found)
        }

        // 한 묶음이 여러 줄의 후보이면 어느 줄 것인지 알 수 없다. 사람이 고른다.
        var usage: [String: Int] = [:]
        for candidates in candidatesByLine {
            for group in candidates { usage[group.id, default: 0] += 1 }
        }

        return zip(lines, candidatesByLine).map { line, candidates in
            let already = existing.contains {
                $0.amount == line.amount
                    && abs($0.datetime.timeIntervalSince(line.datetime)) < 1
            }
            // **후보가 하나뿐이고 그 묶음이 다른 줄에는 안 걸릴 때만** 미리 고른다.
            let auto = (candidates.count == 1 && usage[candidates[0].id] == 1)
                ? candidates[0].id : nil
            let isTransfer = accountByAlias[(line.description ?? "").normalizedName] != nil
            return StatementMatch(line: line,
                                  alreadyImported: already,
                                  candidates: candidates,
                                  chosenId: already ? nil : auto,
                                  isInternalTransfer: isTransfer)
        }
    }
}
