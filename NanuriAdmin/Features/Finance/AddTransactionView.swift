import SwiftUI

/// 거래를 손으로 넣는 화면. 재정 탭 ⋯ 메뉴가 연다.
///
/// **농협은 이 길뿐이다.** 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이
/// 농협 앱 화면을 보고 옮겨 적는 수밖에 없다. 2026-08 기준 농협 25건 / 모임 22건이라
/// **절반은 영영 수기다.**
///
/// 그래서 이 화면의 설계 목표는 하나다 — **연달아 넣기가 빨라야 한다.**
///
/// - **저장해도 닫히지 않는다.** 한 건 넣을 때마다 시트를 다시 여는 건 25번 반복할
///   동작이 아니다. 저장하면 금액과 적요만 비우고 그 자리에서 다음 건을 받는다.
/// - **일시·통장·종류·분류는 남는다.** 장부는 같은 날 여러 건이 몰린다 (8/5 에 7건).
///   매번 다시 고르게 하면 그게 제일 큰 낭비다.
/// - **금액에 포커스가 돌아온다.** 저장 직후 바로 다음 숫자를 칠 수 있다.
/// - **분류를 묻지 않는다.** 넣을 때마다 카테고리를 고르는 건 25번 반복하기에
///   무거운 동작이고, 그 자리에서는 무엇으로 묶을지 정하기도 어렵다. **목록을
///   훑으며 붙이는 편이 낫다** — 비슷한 줄이 나란히 보이니 이름이 저절로 정해진다.
///   분류는 목록에서 줄을 눌러 붙인다.
/// - 넣은 건수를 세어 보여준다. 25건을 넣는 동안 어디까지 왔는지가 보여야 한다.
///
/// **통장을 묻지 않는다** — 기본이 농협이다. 손으로 넣는 건 곧 농협이라
/// (`ARCHITECTURE.md` "통장은 입력 경로가 정한다") 고르는 자리를 앞에 두지 않고,
/// 예외는 아래쪽 통장 칸에서 바꾼다.
struct AddTransactionView: View {
    @ObservedObject var viewModel: FinanceViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    /// 처음 열 때 보고 있던 달. 그 달 1일로 시작한다 — 8월 장부를 쓰는 중이면
    /// 오늘(9월)이 아니라 8월이 기본이라야 한다.
    @State private var datetime: Date
    @State private var isDeposit = false
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var accountId: UUID?
    @State private var counterAccountId: UUID?

    @State private var isSaving = false
    /// 이번에 몇 건 넣었나. 연달아 넣는 화면이라 진행이 보여야 한다.
    @State private var savedCount = 0

    init(viewModel: FinanceViewModel) {
        self.viewModel = viewModel
        _datetime = State(initialValue: viewModel.currentMonth)
        _accountId = State(initialValue: viewModel.account(named: "농협")?.id
                           ?? viewModel.accounts.first?.id)
    }

    private var magnitude: Int { Int(amountText) ?? 0 }
    private var canSave: Bool { magnitude > 0 && accountId != nil && !isSaving }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("일시", selection: $datetime, displayedComponents: [.date])

                    Picker("종류", selection: $isDeposit) {
                        Text("입금").tag(true)
                        Text("출금").tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                        Text("원").foregroundColor(DS.Ink.secondary)
                    }

                    TextField("적요 (예: 헌금, 심방비)", text: $descriptionText)
                } header: {
                    Text("거래")
                }

                Section {
                    Picker("통장", selection: Binding(
                        get: { accountId ?? viewModel.accounts.first?.id ?? UUID() },
                        set: { accountId = $0 }
                    )) {
                        ForEach(viewModel.accounts) { Text($0.name).tag($0.id) }
                    }
                    transferRows
                } footer: {
                    Text("농협 거래를 옮겨 적는 화면이에요. 모임통장은 거래내역서를 불러오면 자동으로 채워져요.")
                }
            }
            .navigationTitle(savedCount == 0 ? "거래 추가" : "거래 추가 (\(savedCount)건)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("저장") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { amountFocused = true }
        }
    }

    /// 내부 이체 표시. 농협에서 모임으로 예산을 넘긴 줄이 이걸로 들어간다.
    /// **한 줄이 양쪽 통장을 안다** — 두 줄로 적지 않는다.
    @ViewBuilder
    private var transferRows: some View {
        let others = viewModel.accounts.filter { $0.id != accountId }
        if let fallback = others.first {
            Toggle("통장 사이 이체", isOn: Binding(
                get: { counterAccountId != nil },
                set: { counterAccountId = $0 ? fallback.id : nil }
            ))

            if counterAccountId != nil {
                Picker("상대 통장", selection: Binding(
                    get: { counterAccountId ?? fallback.id },
                    set: { counterAccountId = $0 }
                )) {
                    ForEach(others) { Text($0.name).tag($0.id) }
                }
            }
        }
    }

    /// 저장하고 **그 자리에서 다음 건을 받는다.** 비우는 건 금액과 적요뿐이다.
    private func save() {
        guard let accountId else { return }
        Task {
            isSaving = true
            let ok = await viewModel.addTransaction(
                accountId: accountId,
                // 자기 자신과의 이체는 이체가 아니다 (DB 에도 check 가 걸려 있다).
                counterAccountId: counterAccountId == accountId ? nil : counterAccountId,
                datetime: datetime,
                amount: isDeposit ? magnitude : -magnitude,
                description: descriptionText.isEmpty ? nil : descriptionText
            )
            isSaving = false
            guard ok else { return }   // 실패하면 입력을 지우지 않는다. 다시 누르면 된다.
            savedCount += 1
            amountText = ""
            descriptionText = ""
            amountFocused = true
        }
    }
}
