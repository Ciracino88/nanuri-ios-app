import SwiftUI

/// 헤더 아래에 놓는 검색 입력.
///
/// `.searchable` 을 쓰지 않는다. 그건 내비게이션 바가 있어야 나오는데 모든 탭이
/// 내비게이션 바를 숨기고 `AdminHeaderView` 를 직접 그리기 때문이다.
///
/// 원문 Search-field 자리다 — 48pt 높이, radius 12, 쉬는 상태는 보조 표면색이고
/// **포커스되면 흰 배경 + 1.5px 파랑 보더**로 한 단 강해진다.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(DS.Icon.font(DS.Icon.m))
                .foregroundColor(isFocused ? DS.Ink.brand : DS.Ink.placeholder)
            TextField(prompt, text: $text)
                .typeStyle(DS.Typo.body2)
                .foregroundColor(DS.Ink.primary)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Icon.font(DS.Icon.m))
                        .foregroundColor(DS.Ink.placeholder)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, DS.Spacing.medium)
        .frame(height: DS.Size.field)
        .background(isFocused ? DS.Surface.card : DS.Surface.secondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .strokeBorder(
                    isFocused ? DS.Line.focused : DS.Line.default,
                    lineWidth: isFocused ? DS.Line.focusedWidth : DS.Line.hairline
                )
        )
        .animation(DS.Motion.control, value: isFocused)
    }
}
