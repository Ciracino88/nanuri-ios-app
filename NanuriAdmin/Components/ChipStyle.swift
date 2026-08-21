import SwiftUI

extension View {
    /// 읽기 전용 배지 (상태 라벨, 카테고리 태그).
    ///
    /// 원문 Badge 자리다 — 22pt 높이에 6px 라운드로 **칩보다 작고 정보 밀도가 높다.**
    /// 색은 `DS.Tone` 이 글자색과 옅은 바탕을 짝으로 들고 있다.
    func tagChip(_ tone: DS.ColorTone) -> some View {
        self
            .typeStyle(DS.Typo.captionS)
            .padding(.horizontal, DS.Spacing.small)
            .frame(height: DS.Size.badge)
            .background(tone.surface)
            .foregroundColor(tone.content)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs + 2))
    }

    /// 선택형 칩 (탭으로 토글).
    ///
    /// 원문 Chip 자리다 — 34pt 높이의 full pill 이고, **쉬는 상태는 흰 바탕 +
    /// 헤어라인 보더**, 선택되면 `grey900` 으로 채워지고 글자가 흰색으로 뒤집힌다.
    ///
    /// 선택색이 파랑이 아닌 게 핵심이다. 파랑은 화면당 하나뿐인 주요 동작에
    /// 예약돼 있어서, 필터 칩까지 파랑으로 칠하면 강조가 둘이 된다.
    func selectableChip(isSelected: Bool) -> some View {
        self
            .typeStyle(DS.Typo.labelS)
            .padding(.horizontal, DS.Spacing.medium)
            .frame(height: DS.Size.chip)
            .background(isSelected ? DS.Ink.primary : DS.Surface.card)
            .foregroundColor(isSelected ? DS.Ink.inverse : DS.Ink.secondary)
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(DS.Line.default, lineWidth: DS.Line.hairline)
                }
            }
    }
}
