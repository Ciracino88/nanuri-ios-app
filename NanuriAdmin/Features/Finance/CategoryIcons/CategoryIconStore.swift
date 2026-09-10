import SwiftUI
import Combine

/// **카테고리 → 아이콘 매핑을 기기에 저장한다.**
///
/// 이건 회계 데이터가 아니라 **표시 취향**이다 — "어느 카테고리 옆에 어떤 그림을
/// 보일까". 그래서 Supabase 가 아니라 기기 로컬(`UserDefaults`)에 둔다. 알림함
/// (`NotificationStore`)이 쓰는 것과 같은 기기-로컬 저장 문법이다. 기기를 바꾸면
/// 다시 골라야 하지만, 잔액·보고서·장부 정본은 하나도 영향받지 않는다.
///
/// 키는 **카테고리 문자열 그대로**다. 카테고리는 고정 목록이 없고 자유 문자열이라
/// (`finance_items.category`), 이름을 바꾸면 매핑이 옛 이름에 남는다 — 그건 사람이
/// 아이콘 화면에서 다시 정리하면 된다. 이 저장소는 "지금 이 이름엔 이 그림" 만 안다.
///
/// **`@Published mapping` 이 바뀌면** 이걸 들고 있는 `FinanceView` 가 다시 그려지고,
/// 목록 행이 새 그림으로 바뀐다.
@MainActor
final class CategoryIconStore: ObservableObject {
    /// 카테고리(정규화된 문자열) → 아이콘 `id`.
    @Published private(set) var mapping: [String: String] = [:]

    private let storageKey = "categoryIcons.v1"

    init() { load() }

    /// 이 카테고리에 정해 둔 아이콘 `id`. 없으면 `nil`.
    func iconId(for category: String?) -> String? {
        guard let key = Self.normalize(category) else { return nil }
        return mapping[key]
    }

    /// 이 카테고리에 붙일 아이콘. `nil` 이면 지운다(아이콘 없음).
    func set(_ iconId: String?, for category: String) {
        guard let key = Self.normalize(category) else { return }
        if let iconId { mapping[key] = iconId } else { mapping.removeValue(forKey: key) }
        save()
    }

    /// 아이콘이 붙은 카테고리 개수. 관리 화면 요약에 쓴다.
    var assignedCount: Int { mapping.count }

    // MARK: 저장

    private static func normalize(_ category: String?) -> String? {
        let v = category?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? nil : v
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        mapping = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
