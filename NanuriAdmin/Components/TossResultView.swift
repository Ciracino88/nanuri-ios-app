import SwiftUI

struct TossResultView: View {
    let bill: Bill
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text("송금 결과를 선택해주세요")
                        .font(.headline)
                    Text("\(bill.title)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("\(bill.amount.formatted())원")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                VStack(spacing: 12) {
                    Button {
                        onApprove()
                    } label: {
                        Text("송금 완료")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .font(.headline)
                    }

                    Button {
                        onCancel()
                    } label: {
                        Text("취소")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                            .font(.headline)
                    }
                }
            }
            .padding(24)
            .background(Color.white)
            .cornerRadius(20)
            .padding(.horizontal, 32)
        }
    }
}
