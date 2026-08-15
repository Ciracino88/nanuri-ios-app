import SwiftUI

/// 헤더 아래에 놓는 검색 입력.
///
/// `.searchable` 을 쓰지 않는다. 그건 내비게이션 바가 있어야 나오는데 모든 탭이
/// 내비게이션 바를 숨기고 `AdminHeaderView` 를 직접 그리기 때문이다.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DS.Icon.inline))
                .foregroundColor(.secondary)
            TextField(prompt, text: $text)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DS.Icon.inline))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, DS.Spacing.medium)
        .padding(.vertical, DS.Spacing.small)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}
