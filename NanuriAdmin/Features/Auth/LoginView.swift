import SwiftUI
import Combine

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("나누리 청년부")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("관리자 페이지")
                    .headerTitle()
            }

            Spacer()

            Button {
                Task { await authViewModel.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                    Text("Google로 로그인")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(authViewModel.isLoading)
            .opacity(authViewModel.isLoading ? 0.5 : 1)

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .background(Color(.systemGroupedBackground))
    }
}
