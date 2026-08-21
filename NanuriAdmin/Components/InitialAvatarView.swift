import SwiftUI

/// 이름 한 글자를 담은 원. 청구서 목록 카드가 쓴다.
///
/// 상세 시트에는 없다 — 이름이 상자의 한 줄로 내려가면서 머리의 프로필 영역이
/// 통째로 빠졌다 (`BillDetailView`).
///
/// 사진이 있는 관리자 프로필은 `AvatarView` 를 쓴다. 청구자는 사진이 없다 —
/// 공개 폼이 이름만 받기 때문이다. 목록을 훑을 때 줄을 잡아 주는 표식일 뿐이라
/// **색을 뜻으로 쓰지 않는다.** 사람마다 다른 색을 주면 색이 뜻을 잃는다.
/// 상태는 옆의 상태 배지가 이미 말하고 있다.
struct InitialAvatarView: View {
    let name: String

    var body: some View {
        Circle()
            .fill(DS.Surface.secondary)
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
            .overlay(Text(initial).rowTitle())
    }

    /// 성을 뺀 첫 글자. "김민준" 이면 "민" 이다.
    ///
    /// 한 글자 성을 가정한다. 두 글자 성(남궁·선우)이면 한 글자 밀리지만, 이름은
    /// 바로 옆에 그대로 적혀 있으므로 틀려도 읽는 데 지장이 없다. 성만 쓰면
    /// 청구자가 늘었을 때 같은 글자만 줄줄이 늘어선다.
    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        let isKoreanName = trimmed.count >= 2 && trimmed.count <= 4
            && trimmed.allSatisfy { $0.isHangul }
        if isKoreanName, let second = trimmed.dropFirst().first {
            return String(second)
        }
        return String(first).uppercased()
    }
}

private extension Character {
    var isHangul: Bool {
        unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }
}
