import SwiftUI

/// 거래 편집·항목 편집이 함께 쓰는 작은 섹션들.
///
/// 두 화면은 성격이 달라 따로 두지만(`TransactionEditView`·`PieceEditView`),
/// **금액 히어로·영수증 버튼·삭제**는 글자만 다르고 생김새가 같아서 여기 모은다.

/// **첫 섹션은 금액 하나를 크게 세운다** (토스 결제 결과 화면의 문법).
/// 장부를 열어 가장 먼저 확인하는 건 결국 "얼마" 라, 그 수를 가운데 큰 글씨로 홀로
/// 세우고 나머지 정보는 아래 섹션이 받는다.
///
/// **부호는 색과 캡션이 대신 말한다** — 수는 절댓값으로 두고, 입금·출금·이체는 색과
/// 그 아래 한 단어가 말한다. `amountText` 를 주면 고치는 칸(손입력 거래), 없으면
/// 읽기 전용(조각·거래내역서 거래)이다.
struct AmountHeroSection: View {
    var amountText: Binding<String>?
    let displayAmount: Int
    let color: Color
    let caption: String

    var body: some View {
        Section {
            VStack(spacing: DS.Spacing.tight) {
                if let amountText {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                        TextField("0", text: amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .typeStyle(DS.Typo.display2)
                            .tabularAmount()
                            .foregroundColor(color)
                            .fixedSize()
                        Text("원")
                            .typeStyle(DS.Typo.h3)
                            .foregroundColor(color)
                    }
                } else {
                    Text("\(abs(displayAmount).formatted())원")
                        .typeStyle(DS.Typo.display2)
                        .tabularAmount()
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(caption)
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.medium)
            // 카드 없이 화면 배경 위에 그대로 세운다 — 레퍼런스의 흰 바탕처럼.
            .listRowBackground(Color.clear)
        }
    }
}

/// 영수증은 편집창에 **버튼 하나**로만 둔다 (레퍼런스 문법). 있으면 "보기",
/// 없으면 "추가" — 어느 쪽이든 같은 관리 시트(`ReceiptManagerView`)를 연다.
/// 썸네일·추가·미리보기가 본문을 차지하면 금액·정보가 아래로 밀린다.
struct ReceiptButtonSection: View {
    let receiptCount: Int
    let isSaving: Bool
    let onTap: () -> Void

    var body: some View {
        Section {
            Button(action: onTap) {
                if receiptCount > 0 {
                    Label("영수증 보기 (\(receiptCount)장)", systemImage: "paperclip")
                } else {
                    Label("영수증 추가", systemImage: "plus")
                }
            }
            .disabled(isSaving)
        } header: {
            Text("영수증")
        }
    }
}

/// **되돌릴 수 없는 것이라 빨강이고, 확인을 한 번 받는다.**
/// 실제 확인 대화상자는 각 화면이 붙인다 — 이 섹션은 버튼과 안내문만 그린다.
struct DeleteSection: View {
    let label: String
    let message: String
    let isSaving: Bool
    let onTap: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onTap) {
                HStack {
                    Spacer()
                    Text(label)
                    Spacer()
                }
            }
            .disabled(isSaving)
        } footer: {
            Text(message)
        }
    }
}
