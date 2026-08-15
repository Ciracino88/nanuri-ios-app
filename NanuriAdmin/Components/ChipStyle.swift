import SwiftUI

extension View {
    /// 정적 태그 칩 (읽기 전용 라벨). 예: 카테고리 태그, 상태 배지.
    func tagChip(color: Color) -> some View {
        self
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    /// 선택형 칩 (탭으로 토글). 선택 시 채워지고, 아니면 회색.
    func selectableChip(isSelected: Bool, tint: Color = .blue) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? tint : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}
