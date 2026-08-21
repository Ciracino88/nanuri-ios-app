import SwiftUI

/// 둘·셋을 화면 폭에 균등하게 나눠 갖는 세그먼트 (재정 탭의 전체·입금·출금).
///
/// 원문 Segmented-control 자리다 — 트랙은 보조 표면색이고, **선택된 칸만 흰
/// 배경으로 떠오른다**(가장 약한 그림자 한 단계). 미선택 라벨은 보조 글자색이다.
///
/// 칩이 다중 필터라면 이건 상호 배타적 단일 선택이다.
struct PillPicker: View {
    let tabs: [(label: String, count: Int)]
    @Binding var selection: Int
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                segment(index)
            }
        }
        .padding(DS.Spacing.tight)
        .background(DS.Surface.secondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
    }

    private func segment(_ index: Int) -> some View {
        let isSelected = selection == index
        return Button {
            withAnimation(DS.Motion.control) { selection = index }
        } label: {
            HStack(spacing: DS.Spacing.tight) {
                Text(tabs[index].label)
                    .typeStyle(DS.Typo.labelM)
                Text("\(tabs[index].count)")
                    .typeStyle(DS.Typo.labelS)
                    .tabularAmount()
                    .foregroundColor(isSelected ? DS.Ink.brand : DS.Ink.placeholder)
            }
            .padding(.vertical, DS.Spacing.small)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .fill(DS.Surface.card)
                        .elevation(.menu)
                        .matchedGeometryEffect(id: "pill", in: pillNamespace)
                }
            }
            .foregroundColor(isSelected ? DS.Ink.primary : DS.Ink.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
