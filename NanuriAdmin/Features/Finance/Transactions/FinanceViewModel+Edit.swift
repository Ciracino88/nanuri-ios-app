import Foundation
import UIKit
import Supabase
import OSLog

extension FinanceViewModel {

    /// 고른 항목들에 **카테고리를 한 번에 붙인다.** 빈 문자열이면 지운다.
    /// 항목이 곧 장부 줄이라 한 표(`finance_items`)에 한 요청이면 된다.
    func applyCategory(_ category: String, to rows: [LedgerRow]) async {
        let trimmed = category.trimmingCharacters(in: .whitespaces)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        let ids = rows.map { $0.item.id }
        guard !ids.isEmpty else { return }
        do {
            try await supabase.from("finance_items")
                .update(CategoryPatch(category: value))
                .in("id", values: ids.map(\.uuidString))
                .execute()
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("카테고리 추가 실패: \(error.localizedDescription)")
            return
        }
        // 목록을 다시 받지 않고 그 자리에 꽂는다.
        let idSet = Set(ids)
        for idx in items.indices where idSet.contains(items[idx].id) {
            items[idx].category = value
        }
    }

    // MARK: - 농협 수기 항목

    /// 농협 입출금을 손으로 넣는다. **은행 증명이 없어 항목으로 바로 들어간다**
    /// (`sourceTransactionId == nil`). 농협은 인터넷뱅킹이 없어 이 길뿐이다.
    ///
    /// 넣은 뒤 목록을 다시 받지 않고 돌려받은 행을 그 자리에 꽂는다 — 연달아 넣는
    /// 화면이라 한 건마다 전부 다시 받으면 입력이 끊긴다.
    @discardableResult
    func addManualItem(accountId: UUID, datetime: Date, amount: Int, description: String?) async -> Bool {
        let insert = FinanceItemInsert(accountId: accountId, datetime: datetime,
                                       amount: amount, description: description)
        do {
            let created: FinanceItem = try await supabase
                .from("finance_items")
                .insert(insert)
                .select()
                .single()
                .execute()
                .value
            items.append(created)
            items.sort { $0.datetime > $1.datetime }
            return true
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("항목 추가 실패: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 삭제

    /// 항목을 지운다.
    ///
    /// **은행 증명이 있으면 그 거래 전체를 지운다** — 한 거래에서 나온 형제 항목까지
    /// 함께다(거래를 지우면 항목이 cascade 로 사라진다). 은행 줄 하나를 통째로
    /// 무르는 것이라, 조각 하나만 떼는 건 대조가 어긋나 뜻이 없다. 농협 수기 항목은
    /// 뒤에 거래가 없으니 그 항목만 지운다.
    ///
    /// **영수증을 먼저 지운다** — 행이 먼저 사라지면 R2 에 주인 없는 파일이 남는다.
    func deleteItem(_ item: FinanceItem) async {
        let victims: [FinanceItem] = item.sourceTransactionId
            .map { txId in items.filter { $0.sourceTransactionId == txId } } ?? [item]
        for victim in victims {
            for url in victim.receipts { await ReceiptStorage.delete(receiptUrl: url) }
        }
        do {
            if let txId = item.sourceTransactionId {
                try await supabase.from("finance_transactions").delete().eq("id", value: txId).execute()
                transactions.removeAll { $0.id == txId }
                items.removeAll { $0.sourceTransactionId == txId }
            } else {
                try await supabase.from("finance_items").delete().eq("id", value: item.id).execute()
                items.removeAll { $0.id == item.id }
            }
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("항목 삭제 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 항목 편집 저장 (영수증 R2 는 청구서와 같은 저장소 재사용)

    /// 항목의 **사람 값**(카테고리·적요·영수증)을 고친다. 은행 증명이 있는 항목도
    /// 이건 고칠 수 있다 — 금액·일시·통장은 은행 값이라 안 건드린다.
    func saveItemFields(
        id: UUID,
        category: String?,
        description: String?,
        keptUrls: [String],
        newImages: [UIImage],
        originalUrls: [String]
    ) async {
        let uploaded = await uploadReceipts(newImages)
        let finalUrls = keptUrls + uploaded
        do {
            try await supabase.from("finance_items")
                .update(ItemFieldsUpdate(category: category, description: description, receiptUrls: finalUrls))
                .eq("id", value: id)
                .execute()
            patchItem(id) {
                $0.category = category
                $0.description = description
                $0.receiptUrls = finalUrls
            }
        } catch {
            self.error = error.localizedDescription
            for url in uploaded { await ReceiptStorage.delete(receiptUrl: url) }
            return
        }
        await deleteRemovedReceipts(originalUrls: originalUrls, keptUrls: keptUrls)
    }

    /// 농협 수기 항목의 **전 필드**를 고친다. 은행 증명이 없어 금액·일시·통장까지 열려 있다.
    func saveManualItem(
        id: UUID,
        accountId: UUID,
        datetime: Date,
        amount: Int,
        category: String?,
        description: String?,
        keptUrls: [String],
        newImages: [UIImage],
        originalUrls: [String]
    ) async {
        let uploaded = await uploadReceipts(newImages)
        let finalUrls = keptUrls + uploaded
        do {
            try await supabase.from("finance_items")
                .update(ItemFullUpdate(accountId: accountId, datetime: datetime, amount: amount,
                                       category: category, description: description, receiptUrls: finalUrls))
                .eq("id", value: id)
                .execute()
            patchItem(id) {
                $0.accountId = accountId
                $0.datetime = datetime
                $0.amount = amount
                $0.category = category
                $0.description = description
                $0.receiptUrls = finalUrls
            }
            items.sort { $0.datetime > $1.datetime }
        } catch {
            self.error = error.localizedDescription
            for url in uploaded { await ReceiptStorage.delete(receiptUrl: url) }
            return
        }
        await deleteRemovedReceipts(originalUrls: originalUrls, keptUrls: keptUrls)
    }

    // MARK: - 거들이

    private func patchItem(_ id: UUID, _ mutate: (inout FinanceItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    /// 새 이미지들을 해상도 축소 후 올리고 URL 을 돌려준다.
    private func uploadReceipts(_ images: [UIImage]) async -> [String] {
        var urls: [String] = []
        for image in images {
            guard let jpeg = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.7) else { continue }
            if let uploaded = try? await ReceiptStorage.upload(imageData: jpeg, filename: "receipt.jpg", folder: "finance") {
                urls.append(uploaded)
            }
        }
        return urls
    }

    /// 편집에서 뺀 기존 영수증을 R2 에서 지운다 (DB 반영 성공 뒤에).
    private func deleteRemovedReceipts(originalUrls: [String], keptUrls: [String]) async {
        for url in originalUrls where !keptUrls.contains(url) {
            await ReceiptStorage.delete(receiptUrl: url)
        }
    }
}
