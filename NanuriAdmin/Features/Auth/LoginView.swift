import SwiftUI
import Combine

/// 로그인 화면. 이 화면에서 할 수 있는 일은 하나뿐이라 버튼은 **Primary** 다.
///
/// 예전에는 흰 바탕에 회색 테두리라 화면의 카드들과 구분이 안 됐다. 배경 위에
/// 흰 상자가 하나 놓인 것처럼 보여서, 눌러야 하는 자리라는 게 드러나지 않았다.
struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            Spacer()

            VStack(spacing: DS.Spacing.small) {
                Text("나누리 청년부")
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.secondary)
                Text("관리자 페이지")
                    .typeStyle(DS.Typo.h2)
                    .foregroundColor(DS.Ink.primary)
            }

            Spacer()

            Button {
                Task { await authViewModel.signInWithGoogle() }
            } label: {
                HStack(spacing: DS.Spacing.small) {
                    Image(systemName: "globe")
                        .font(DS.Icon.font(DS.Icon.m))
                    Text("Google로 로그인")
                        .typeStyle(DS.Typo.labelL)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.buttonXL)
                .background(DS.Palette.accent)
                .foregroundColor(DS.Ink.onAccent)
            }
            .buttonStyle(PressOverlayButtonStyle(
                shape: AnyShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
            ))
            .disabled(authViewModel.isLoading)

            if let errorMessage = authViewModel.errorMessage {
                // 에러도 해요체로 안내한다. 사용자를 멈춰 세우지 않는 게 원칙이다.
                Text(errorMessage)
                    .typeStyle(DS.Typo.body3)
                    .foregroundColor(DS.Ink.danger)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.screen)
        .screenBackground()
    }
}
