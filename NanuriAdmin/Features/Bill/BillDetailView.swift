import SwiftUI

/// 청구서 한 건을 처리하는 시트. 카드를 누르면 열린다.
///
/// 청구서로 할 수 있는 일은 **전부 여기 있다** — 영수증 보기 · 송금 · 거절 · 삭제.
/// 목록 카드는 정보만 보여준다 (`BillRowView`). 되돌릴 수 없는 두 개(거절·삭제)는
/// 여기서 확인을 한 번 더 받는다 (DESIGN.md 6번).
///
/// 구조는 **위에서 아래로 한 줄기**다 (DESIGN.md 1번 "영수증 시트의 뼈대").
///
/// ```
/// 198,000원              ← 금액 (34). 이 시트에서 제일 먼저 읽는 것
/// 아직 송금하지 않았어요    ← 상태를 문장 한 줄로. 색이 뜻이다
/// ────────────────       ← 머리와 값을 가르는 선 한 올
/// 이름 · 항목 · 청구일 · 계좌   ← 상자 없이, 줄 사이만 넓게
/// [ 영수증 보기 ]         ← 결정이 아닌 것. 아이콘이 그걸 말해 준다
/// ────────────────
/// [ 거절 ] [ 송금하기 ]    ← 바닥 고정
/// ```
///
/// **닫기 버튼은 두지 않는다.** 위쪽에 드래그 인디케이터가 있어(부모가
/// `presentationDragIndicator(.visible)`) 손잡이로 내린다 — 닫는 자리가
/// 하나면 충분하고, ✕ 를 없애면 맨 위가 곧장 금액으로 시작한다.
///
/// **머리에 프로필 영역을 두지 않는다.** 이름·계좌·상태를 위에 한 번 적고 아래
/// 상자에 또 적으면 같은 값이 한 화면에 두 번 나온다. 이름까지 아래 값 줄로
/// 내리면 값이 적히는 곳은 **한 군데**가 된다. 맨 위는 금액이다 — 이 시트에서
/// 제일 먼저 읽어야 하는 것이고, 그래서 크기를 독점한다 (DESIGN.md 3번).
///
/// 송금은 이 시트가 직접 못 한다. 토스 앱을 열고 돌아와서 "송금했나요?"를 물어야
/// 하는데(`TossResultView`) 시트 위에 시트를 겹치면 두 개를 같이 닫아야 해서,
/// **이 시트는 닫히기만 하고 다음 시트는 `BillListView` 가 연다.**
struct BillDetailView: View {
    let bill: Bill
    /// 이름으로 찾은 계좌. 없으면 송금 대신 계좌 등록을 유도한다.
    let payee: Payee?
    @ObservedObject var viewModel: BillViewModel
    /// 토스로 넘어간다. 시트를 닫는 것까지 이 클로저가 한다.
    let onTransfer: () -> Void
    /// 계좌부 등록 시트로 넘어간다. 계좌를 못 찾았을 때만 쓴다.
    let onRegisterPayee: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showReceipt = false
    @State private var showRejectAlert = false
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Spacing.section) {
                    amount
                    // 머리(금액·상태)와 값을 가르는 선 한 올. 상자를 걷어낸 자리를
                    // 이게 대신한다 — 값 네 줄이 금액에 딸린 설명처럼 붙어 보이면 안 된다.
                    Divider()
                    details
                    ActionButton(title: "영수증 보기", icon: "doc.text", kind: .tinted) {
                        showReceipt = true
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                // 위아래를 한 단계 더 벌린다. 위는 금액(앱에서 가장 큰 글자)이
                // 닫기 버튼에 붙지 않게, 아래는 "영수증 보기"가 바닥에 고정된
                // 버튼에 붙지 않게 — 붙으면 누를 때 잘못 짚는다.
                .padding(.vertical, DS.Spacing.sheetEdge)
            }

            bottomBar
        }
        .presentationDetents(detents)
        .sheet(isPresented: $showReceipt) {
            ReceiptSheetView(receiptUrl: bill.receiptUrl)
        }
        .alert("이 청구서를 거절할까요?", isPresented: $showRejectAlert) {
            Button("거절", role: .destructive) {
                Task {
                    await viewModel.updateStatus(billId: bill.id, status: "rejected")
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("처리 완료로 넘어가고, 앱에서는 다시 대기중으로 되돌릴 수 없어요.")
        }
        .alert("이 청구서를 지울까요?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                Task {
                    await viewModel.deleteBill(billId: bill.id, receiptUrl: bill.receiptUrl)
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("영수증 이미지까지 같이 지워지고 되돌릴 수 없어요.")
        }
    }

    // MARK: - 높이

    /// 시트는 **화면 높이의 정해진 비율**로 열린다 (`DS.Sheet.billDetail`).
    ///
    /// `.medium`(화면 절반)은 하필 "영수증 보기" 버튼 자리에서 잘렸다. 잘린 글은
    /// "아래에 더 있다"는 신호지만 **잘린 버튼은 눌러도 되는 건지부터 헷갈린다.**
    /// 그렇다고 내용을 재서 딱 맞추면 **열 때마다 높이가 달라진다** — 첫 측정이
    /// 크기 바뀌는 도중 어디에 걸리느냐를 타서, 같은 청구서가 어떨 때는 길게
    /// 어떨 때는 짧게 열렸다 (`TROUBLESHOOTING.md`).
    ///
    /// 그래서 **늘 같은 자리에서 열리는 쪽**을 골랐다. 비율은 내용보다 조금 넉넉해서
    /// 남는 자리는 스크롤 안쪽 아래에 생기고, 모자라면 스크롤된다.
    /// `.large` 는 손으로 더 올릴 때를 위해 남긴다.
    private var detents: Set<PresentationDetent> {
        [.fraction(DS.Sheet.billDetail), .large]
    }

    // MARK: - 바닥

    /// 바닥 버튼은 스크롤을 안 따라간다. 시트를 손으로 올려 내용이 이 선에서
    /// 잘릴 때, 선과 여백이 "여기까지가 읽는 자리"를 갈라 준다 (DESIGN.md 6번).
    /// 이게 없으면 잘린 내용이 버튼에 붙어 한 덩어리로 보인다.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            actions
                .padding(DS.Spacing.screen)
        }
    }

    // MARK: - 내용

    /// 시트에서 제일 먼저 읽어야 하는 자리. 크기를 여기에 몰아준다.
    ///
    /// 금액 아래는 **상태 한 줄**이다. 목록 카드에서는 칩(`statusLabel`)이지만
    /// 여기서는 문장으로 적는다 — 한 건만 들여다보는 자리라 배지로 줄여 쓸
    /// 이유가 없다. 색은 카드의 칩과 같은 `statusColor` 다. 색이 뜻이라서
    /// 대기(주황)·완료(초록)·거절(빨강)이 화면마다 같아야 한다 (DESIGN.md 5번).
    private var amount: some View {
        VStack(spacing: DS.Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                Text(bill.amount.formatted())
                    .heroAmount()
                Text("원")
                    .amountUnit()
            }
            Text(bill.statusSentence)
                .sheetSubtext()
                .foregroundColor(bill.statusColor)
        }
        .frame(maxWidth: .infinity)
    }

    /// 이름·항목·청구일·계좌. **이 시트에서 값이 적히는 곳은 여기 하나뿐이다.**
    ///
    /// 상자(`.groupBox()`)도 줄 사이 구분선도 없다. 시트에서 이 값들은 **곁가지가
    /// 아니라 내용 자체**라, 묶어 봐야 묶일 상대가 없고 테두리만 남는다.
    /// 대신 줄 간격을 한 단계 넓혀서(`section`) 라벨-값 짝이 가로로 읽히게 한다 —
    /// 선을 그어 나누던 일을 여백이 한다. (`.groupBox()` 는 값 덩어리가 다른
    /// 내용과 섞이는 `TossResultView` 에 남아 있다.)
    private var details: some View {
        VStack(spacing: DS.Spacing.section) {
            detailRow("이름", bill.submitterName)
            detailRow("항목", bill.title)
            // 기기 언어가 영어여도 한국어로 나와야 한다. `formatted()` 는 로케일을 탄다.
            detailRow("청구일", bill.createdAt.koreanDateTimeString)
            // 계좌가 없어도 줄을 지우지 않는다. 없다는 사실이 여기서 할 결정을
            // 바꾸므로(송금 대신 계좌 등록) 주황으로 적어 둔다.
            detailRow(
                "계좌",
                payee?.accountLine ?? "계좌 미등록",
                color: payee == nil ? DS.Palette.pending : nil
            )
        }
    }

    private func detailRow(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .sheetSubtext()
            Spacer(minLength: DS.Spacing.medium)
            Text(value)
                .sheetTitle()
                .foregroundColor(color ?? .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 처리 버튼

    /// 대기중이면 처리하는 자리고, 처리된 뒤에는 지우는 자리다.
    /// 계좌를 못 찾았으면 송금 대신 계좌 등록이 들어온다 — 등록이 먼저다.
    ///
    /// 처리된 청구서에 남는 동작은 삭제 하나라 **가로를 다 쓴다.** 닫기는
    /// 드래그 인디케이터가 맡으므로 바닥에 짝지을 버튼이 없다.
    @ViewBuilder
    private var actions: some View {
        if bill.isPending {
            HStack(spacing: DS.Spacing.small) {
                ActionButton(title: "거절", kind: .destructive) { showRejectAlert = true }
                if payee != nil {
                    ActionButton(title: "송금하기", kind: .primary, action: onTransfer)
                } else {
                    ActionButton(title: "계좌 등록하기", kind: .primary, action: onRegisterPayee)
                }
            }
        } else {
            ActionButton(title: "삭제", kind: .destructive) { showDeleteAlert = true }
        }
    }
}

// MARK: - 영수증

struct ReceiptSheetView: View {
    let receiptUrl: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let url = URL(string: receiptUrl) {
                    // 화면에 그릴 크기로 줄여서 디코드하고, 받은 건 캐시에 남는다.
                    // 시트를 닫았다 열어도 다시 안 받는다 (`RemoteImage`).
                    RemoteImage(url: url, maxDimension: DS.Size.fullPhoto) {
                        ProgressView()
                    } failure: {
                        VStack(spacing: DS.Spacing.medium) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(DS.Icon.font(DS.Icon.placeholder))
                                .foregroundColor(DS.Ink.placeholder)
                            Text("이미지를 불러올 수 없어요")
                                .typeStyle(DS.Typo.body2)
                                .foregroundColor(DS.Ink.secondary)
                        }
                    }
                    .scaledToFit()
                    .padding()
                }
            }
            .navigationTitle("영수증")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
