import SwiftUI

/// 농협 항목을 손으로 넣는 화면.
///
/// 농협은 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이 앱 화면을 보고
/// 옮겨 적는 수밖에 없다. 한 달에 25건 안팎을 연달아 넣는다. 그래서 이 화면의
/// 설계 목표는 하나다 — **빠르고 가볍게.**
///
/// **금액이 주인공이다.** 토스 송금 문법처럼 금액을 화면 위 큰 글씨로 세우고
/// 키패드에 바로 포커스한다. 그 아래 입금/출금, 적요가 오고, **날짜·통장은
/// 기본값("그 달 · 농협")으로 접어 둔다** — 대개 안 건드리는 값이라 첫 화면을
/// 차지할 이유가 없다. 필요할 때만 펼친다.
///
/// - **저장해도 닫히지 않는다.** 저장하면 금액과 적요만 비우고 그 자리에서 다음
///   건을 받는다. 날짜·통장·종류는 남는다 (같은 날 여러 건이 몰린다 — 8/5 에 7건).
/// - **금액에 포커스가 돌아온다.** 저장 직후 바로 다음 숫자를 칠 수 있다.
/// - **카테고리를 묻지 않는다.** 넣을 때마다 고르는 건 무거운 동작이라, 목록에서
///   선택 모드로 훑으며 붙이는 편이 낫다. 비슷한 항목이 나란히 보이니 이름이
///   저절로 정해진다.
/// - 넣은 건수를 제목에 센다.
///
/// **내부 이체 토글은 없다.** 농협↔모임 이체는 반드시 모임통장을 지나 거래내역서에
/// 찍히므로 불러오기로 들어온다 — 손으로 적으면 같은 사건이 두 줄이 된다.
///
/// 손으로 넣는 건 은행 증명이 없어 거래가 아니라 **항목**으로 바로 들어간다
/// (`addManualItem`, `sourceTransactionId == nil`).
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
    /// 날짜·통장을 펼쳤는가. 기본은 접힘 — 대개 기본값 그대로 쓴다.
    @State private var showDetails = false

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
    /// 금액 색. 목록 줄과 같은 규칙 — 입금 파랑 · 출금 검정.
    private var amountColor: Color { isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal }
    private func accountName(_ id: UUID?) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "농협"
    }

    var body: some View {
        NavigationView {
            Form {
                // 금액 히어로 — 화면 위에 크게. 카드 없이 바탕 위에 그대로 세운다.
                Section {
                    VStack(spacing: DS.Spacing.medium) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                            TextField("0", text: $amountText)
                                .keyboardType(.numberPad)
                                .focused($amountFocused)
                                .multilineTextAlignment(.center)
                                .typeStyle(DS.Typo.display2)
                                .tabularAmount()
                                .foregroundColor(amountColor)
                                .fixedSize()
                            Text("원")
                                .typeStyle(DS.Typo.h3)
                                .foregroundColor(amountColor)
                        }
                        Picker("종류", selection: $isDeposit) {
                            Text("출금").tag(false)
                            Text("입금").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.medium)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("적요 (예: 헌금, 심방비)", text: $descriptionText)
                }

                // 날짜·통장은 접어 둔다. 요약 줄을 눌러 펼친다.
                Section {
                    Button {
                        withAnimation(DS.Motion.control) { showDetails.toggle() }
                    } label: {
                        LabeledContent("날짜 · 통장") {
                            HStack(spacing: DS.Spacing.tight) {
                                Text("\(datetime.koreanDateString) · \(accountName(accountId))")
                                    .foregroundColor(DS.Ink.secondary)
                                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                    .font(DS.Icon.font(DS.Icon.s))
                                    .foregroundColor(DS.Ink.placeholder)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if showDetails {
                        DatePicker("날짜", selection: $datetime, displayedComponents: [.date])
                        Picker("통장", selection: Binding(
                            get: { accountId ?? viewModel.accounts.first?.id ?? UUID() },
                            set: { accountId = $0 }
                        )) {
                            ForEach(viewModel.accounts) { Text($0.name).tag($0.id) }
                        }
                    }
                } footer: {
                    Text("농협 거래를 옮겨 적는 화면이에요. 저장해도 안 닫히고, 날짜·통장은 그대로 남아요. 모임통장은 거래내역서를 불러오면 자동으로 채워져요.")
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

    /// 저장하고 **그 자리에서 다음 건을 받는다.** 비우는 건 금액과 적요뿐이다.
    private func save() {
        guard let accountId else { return }
        Task {
            isSaving = true
            let ok = await viewModel.addManualItem(
                accountId: accountId,
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
