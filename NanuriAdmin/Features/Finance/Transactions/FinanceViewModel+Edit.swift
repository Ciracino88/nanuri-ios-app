import Foundation
import UIKit
import Supabase
import OSLog

extension FinanceViewModel {

    /// 고른 항목들에 **카테고리를 한 번에 붙인다.** 빈 문자열이면 지운다.
    ///
    /// **건별로 나눠 보내지 않는다.** 조각은 조각끼리, 거래는 거래끼리 한 요청씩
    /// 두 번이다. 나눠 보내면 중간에 끊겼을 때 일부만 붙은 채로 남는다.
    func applyCategory(_ category: String, to rows: [LedgerRow]) async {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        let splitIds = rows.compactMap { $0.split?.id }
        let txIds = rows.filter { $0.split == nil }.map { $0.transaction.id }
        guard !splitIds.isEmpty || !txIds.isEmpty else { return }

        do {
            if !splitIds.isEmpty {
                try await supabase.from("finance_splits")
                    .update(CategoryPatch(category: value))
                    .in("id", values: splitIds.map(\.uuidString))
                    .execute()
            }
            if !txIds.isEmpty {
                try await supabase.from("finance_transactions")
                    .update(CategoryPatch(category: value))
                    .in("id", values: txIds.map(\.uuidString))
                    .execute()
            }
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("카테고리 추가 실패: \(error.localizedDescription)")
            return
        }

        // 목록을 다시 받지 않고 그 자리에 꽂는다. 스무 줄에 붙이고 나서 화면이
        // 통째로 다시 그려지면 어디를 보고 있었는지를 잃는다.
        let splitSet = Set(splitIds)
        for (txId, pieces) in splitsByTransaction {
            guard pieces.contains(where: { splitSet.contains($0.id) }) else { continue }
            splitsByTransaction[txId] = pieces.map { piece in
                var copy = piece
                if splitSet.contains(piece.id) { copy.category = value }
                return copy
            }
        }
        let txSet = Set(txIds)
        for idx in transactions.indices where txSet.contains(transactions[idx].id) {
            transactions[idx].category = value
        }
    }

    // MARK: - 거래 쓰기

    /// 거래를 손으로 넣는다.
    ///
    /// **농협은 이 길뿐이다.** 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이
    /// 앱 화면을 보고 옮겨 적는 수밖에 없다. 2026-08 기준 농협 25건 / 모임 22건이라
    /// **절반은 영영 수기다** — 한 건 넣는 데 손이 많이 가면 안 쓰게 된다.
    ///
    /// 넣은 뒤 목록을 다시 받지 않고 **돌려받은 행을 그 자리에 꽂는다.** 연달아
    /// 넣는 화면이라 한 건마다 273건을 다시 받으면 입력이 끊긴다.
    @discardableResult
    func addTransaction(
        accountId: UUID,
        counterAccountId: UUID? = nil,
        datetime: Date,
        amount: Int,
        description: String?
    ) async -> Bool {
        guard let ledgerId = currentLedger?.id else {
            error = "장부를 먼저 선택해주세요."
            return false
        }
        let row = BankTransactionInsert(
            ledgerId: ledgerId,
            accountId: accountId,
            counterAccountId: counterAccountId,
            datetime: datetime,
            // 토스가 주는 값(이자입금·체크카드결제·ATM출금…)과 달리 손으로 넣는 건
            // 부호만으로 충분하다. 통장에 찍힌 유형이 아니라 사람이 적는 줄이다.
            type: amount >= 0 ? "입금" : "출금",
            amount: amount,
            description: description,
            // **카테고리는 여기서 안 받는다.** 넣을 때마다 고르는 건 스무 번 넘게
            // 반복하기에 무거운 동작이고, 그 자리에서는 무엇으로 묶을지 정하기도
            // 어렵다. 목록을 훑으며 붙이는 편이 낫다 — 비슷한 항목이 나란히 보이니
            // 이름이 저절로 정해진다.
            source: .manual
        )
        do {
            let created: BankTransaction = try await supabase
                .from("finance_transactions")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            transactions.append(created)
            // `fetchTransactions` 가 datetime 내림차순으로 받으므로 같은 순서를 지킨다.
            transactions.sort { $0.datetime > $1.datetime }
            return true
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래 추가 실패: \(error.localizedDescription)")
            return false
        }
    }

    /// 거래를 지운다. 분할은 `on delete cascade` 로 같이 사라진다.
    ///
    /// **영수증을 먼저 지운다.** 청구서 삭제와 같은 순서이고 이유도 같다 — 행이
    /// 먼저 사라지면 이미지 삭제가 실패했을 때 R2 에 주인 없는 파일이 남고 그 URL 을
    /// 아는 사람이 없어진다. 반대 순서면 최악이 "이미지는 지워졌는데 행이 남는"
    /// 것이고, 그건 눈에 보여서 다시 지울 수 있다.
    func deleteTransaction(_ transaction: BankTransaction) async {
        for url in transaction.receipts {
            await ReceiptStorage.delete(receiptUrl: url)
        }
        do {
            try await supabase
                .from("finance_transactions")
                .delete()
                .eq("id", value: transaction.id)
                .execute()
            transactions.removeAll { $0.id == transaction.id }
            splitsByTransaction[transaction.id] = nil
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래 삭제 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 거래 편집 저장 (영수증 R2는 청구서와 동일한 저장소 재사용)

    /// 거래 편집을 한 번에 커밋한다.
    /// 저장 시점에만 R2 업로드/삭제와 DB 반영이 일어난다 (취소하면 아무 일도 없음).
    /// - Parameters:
    ///   - keptUrls: 유지할 기존 영수증 URL 목록
    ///   - newImages: 새로 추가한 이미지 (여기서 업로드)
    ///   - originalUrls: 편집 시작 시점의 영수증 목록 (제거분 계산용)
    func saveTransactionEdits(
        id: UUID,
        datetime: Date,
        amount: Int,
        description: String?,
        accountId: UUID,
        counterAccountId: UUID?,
        category: String?,
        keptUrls: [String],
        newImages: [UIImage],
        originalUrls: [String],
        splits: [(category: String?, amount: Int, description: String?)] = []
    ) async {
        // 거래내역서에서 온 거래는 **금액·일시·통장이 통장의 기록**이다. 화면이
        // 그 칸을 잠그지만, 잠그는 판단은 여기서도 한 번 더 한다 — 규칙이 화면에만
        // 있으면 화면이 하나 더 생길 때 조용히 새어 나간다.
        let existing = transactions.first { $0.id == id }
        let locked = existing?.isFromStatement ?? false
        let finalDatetime = locked ? (existing?.datetime ?? datetime) : datetime
        let finalAmount   = locked ? (existing?.amount ?? amount) : amount
        let finalAccount  = locked ? (existing?.accountId ?? accountId) : accountId
        // **상대 통장은 잠그지 않는다.** 금액·일시·통장은 은행이 말해 주는 사실이지만
        // "이게 통장 사이 이체인가" 는 **은행이 말해 줄 수 없는 회계 판단**이다 —
        // 거래내역서에는 그 정보가 없고, 적요를 보고 사람이 정한다. 매처가 대신
        // 해 주지만 못 잡을 수도 있고, 판정이 생기기 전에 들어온 줄은 아예 못 만난다.
        // 잠그면 그런 줄을 앱 안에서 고칠 길이 없어진다 (2026-09-03 에 실제로 그랬다).
        let finalCounter  = counterAccountId
        // 1. 새 이미지 업로드 (해상도 축소 후)
        var newlyUploaded: [String] = []
        for image in newImages {
            guard let jpeg = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.7) else { continue }
            if let uploaded = try? await ReceiptStorage.upload(
                imageData: jpeg,
                filename: "receipt.jpg",
                folder: "finance"
            ) {
                newlyUploaded.append(uploaded)
            }
        }

        let finalUrls = keptUrls + newlyUploaded

        // 2. DB 반영 (한 번에)
        do {
            try await supabase
                .from("finance_transactions")
                .update(TransactionEditUpdate(
                    datetime: finalDatetime, amount: finalAmount, description: description,
                    category: category, receiptUrls: finalUrls,
                    accountId: finalAccount, counterAccountId: finalCounter
                ))
                .eq("id", value: id)
                .execute()
            if let idx = transactions.firstIndex(where: { $0.id == id }) {
                transactions[idx].datetime = finalDatetime
                transactions[idx].amount = finalAmount
                transactions[idx].description = description
                transactions[idx].accountId = finalAccount
                transactions[idx].counterAccountId = finalCounter
                transactions[idx].category = category
                transactions[idx].receiptUrls = finalUrls
            }
        } catch {
            self.error = error.localizedDescription
            // DB 반영 실패 시 방금 올린 이미지는 롤백(R2에서 삭제)
            for url in newlyUploaded { await ReceiptStorage.delete(receiptUrl: url) }
            return
        }

        // 3. DB 반영 성공 후, 제거된 기존 영수증을 R2에서 삭제
        let removed = originalUrls.filter { !keptUrls.contains($0) }
        for url in removed { await ReceiptStorage.delete(receiptUrl: url) }

        // 4. 분할 항목 교체 (기존 삭제 후 새로 삽입)
        do {
            try await supabase.from("finance_splits").delete().eq("transaction_id", value: id).execute()
            if splits.isEmpty {
                splitsByTransaction[id] = nil
            } else {
                let inserts = splits.enumerated().map { index, s in
                    TransactionSplitInsert(transactionId: id, amount: s.amount,
                                           category: s.category, description: s.description,
                                           sortOrder: index)
                }
                try await supabase.from("finance_splits").insert(inserts).execute()
                splitsByTransaction[id] = splits.enumerated().map { index, s in
                    TransactionSplit(id: UUID(), transactionId: id, amount: s.amount,
                                     category: s.category, description: s.description,
                                     sortOrder: index)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
