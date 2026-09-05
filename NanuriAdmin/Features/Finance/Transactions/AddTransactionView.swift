import SwiftUI

/// 농협 항목을 손으로 넣는 화면.
///
/// 농협은 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이 앱 화면을 보고
/// 옮겨 적는 수밖에 없다. 한 달에 25건 안팎을 연달아 넣는다. 그래서 이 화면의
/// 설계 목표는 하나다 — **빠르고 가볍게.**
///
/// **금액이 주인공이고, 토스처럼 커스텀 숫자패드로 넣는다.** 시스템 키보드가
/// 아니라 화면 하단에 고정된 패드가 금액을 몰아서, 열고 닫히는 애니메이션 없이
/// 늘 같은 자리에 있고 요약 줄을 가리지도 않는다. 금액을 화면 위 큰 글씨로 세우고,
/// 그 아래 입금/출금·적요가 오며, **날짜·통장은 기본값("그 달 · 농협")으로 접어
/// 둔다** — 대개 안 건드리는 값이라 첫 화면을 차지할 이유가 없다.
///
/// **적요는 텍스트라 시스템 키보드가 필요하다.** 적요를 누르면 숫자패드가 숨고
/// 시스템 키보드가 올라온다. 금액 쪽을 다시 누르면 키보드가 내려가고 패드가 돌아온다.
///
/// - **저장해도 닫히지 않는다.** 저장하면 금액과 적요만 비우고 그 자리에서 다음
///   건을 받는다. 날짜·통장·종류는 남는다 (같은 날 여러 건이 몰린다 — 8/5 에 7건).
/// - **카테고리를 묻지 않는다.** 목록에서 선택 모드로 훑으며 붙이는 편이 낫다.
/// - 넣은 건수를 제목에 센다.
///
/// **내부 이체 토글은 없다.** 농협↔모임 이체는 반드시 모임통장을 지나 거래내역서로
/// 들어온다. 손으로 넣는 건 은행 증명이 없어 거래가 아니라 **항목**으로 바로 들어간다
/// (`addManualItem`, `sourceTransactionId == nil`).
struct AddTransactionView: View {
    @ObservedObject var viewModel: FinanceViewModel

    @Environment(\.dismiss) private var dismiss
    /// 적요 입력 중인가. 켜지면 시스템 키보드가 올라오고 숫자패드는 숨는다.
    @FocusState private var descFocused: Bool

    @State private var datetime: Date
    @State private var isDeposit = false
    /// 금액의 숫자만 (콤마 없이). 커스텀 패드가 이걸 민다.
    @State private var amountDigits = ""
    @State private var descriptionText = ""
    @State private var accountId: UUID?
    /// 날짜·통장을 펼쳤는가. 기본은 접힘 — 대개 기본값 그대로 쓴다.
    @State private var showDetails = false

    @State private var isSaving = false
    @State private var savedCount = 0

    init(viewModel: FinanceViewModel) {
        self.viewModel = viewModel
        _datetime = State(initialValue: viewModel.currentMonth)
        _accountId = State(initialValue: viewModel.account(named: "농협")?.id
                           ?? viewModel.accounts.first?.id)
    }

    private var magnitude: Int { Int(amountDigits) ?? 0 }
    private var canSave: Bool { magnitude > 0 && accountId != nil && !isSaving }
    /// 금액 색. 목록 줄과 같은 규칙 — 입금 파랑 · 출금 검정.
    private var amountColor: Color { isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal }
    private func accountName(_ id: UUID?) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "농협"
    }

    var body: some View {
        NavigationView {
            Form {
                heroSection
                Section {
                    TextField("적요 (예: 헌금, 심방비)", text: $descriptionText)
                        .focused($descFocused)
                }
                detailsSection
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
            // 적요를 안 만지는 동안엔 하단에 커스텀 숫자패드를 고정한다.
            // 적요를 누르면(descFocused) 패드를 걷어 시스템 키보드에 자리를 내준다.
            .safeAreaInset(edge: .bottom) {
                if !descFocused {
                    AmountKeypad(
                        onDigit: { d in
                            // 앞자리 0 은 안 쌓는다. 최대 9자리(≈10억).
                            guard amountDigits.count < 9 else { return }
                            if amountDigits.isEmpty && (d == "0" || d == "00") { return }
                            amountDigits += d
                        },
                        onBackspace: { amountDigits = String(amountDigits.dropLast()) }
                    )
                }
            }
        }
    }

    /// 금액 히어로 — 화면 위 큰 글씨. 누르면 시스템 키보드를 내리고 숫자패드로 돌아온다.
    private var heroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.medium) {
                Button {
                    descFocused = false
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                        Text(amountDigits.isEmpty ? "0" : magnitude.formatted())
                            .typeStyle(DS.Typo.display2)
                            .tabularAmount()
                            .foregroundColor(amountDigits.isEmpty ? DS.Ink.placeholder : amountColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("원")
                            .typeStyle(DS.Typo.h3)
                            .foregroundColor(amountDigits.isEmpty ? DS.Ink.placeholder : amountColor)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Picker("종류", selection: $isDeposit) {
                    Text("출금").tag(false)
                    Text("입금").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.vertical, DS.Spacing.medium)
            .listRowBackground(Color.clear)
        }
    }

    /// 날짜·통장은 접어 둔다. 요약 줄을 눌러 펼친다.
    private var detailsSection: some View {
        Section {
            Button {
                descFocused = false
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
            guard ok else { return }
            savedCount += 1
            amountDigits = ""
            descriptionText = ""
            descFocused = false   // 숫자패드로 돌아와 다음 금액을 바로 친다
        }
    }
}

/// 토스식 커스텀 숫자패드. 화면 하단에 고정된다 — 열고 닫히는 애니메이션이 없다.
private struct AmountKeypad: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void

    private let keys = ["1","2","3","4","5","6","7","8","9","00","0","⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                  spacing: DS.Spacing.tight) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if key == "⌫" { onBackspace() } else { onDigit(key) }
                } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left")
                                .font(DS.Icon.font(DS.Icon.action))
                        } else {
                            Text(key).typeStyle(DS.Typo.h3)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonXL)
                    .foregroundColor(DS.Ink.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.screen)
        .padding(.top, DS.Spacing.small)
        .padding(.bottom, DS.Spacing.tight)
        // 목록과 갈라 보이게 위에 선을 긋고 카드 바탕에 앉힌다 (DESIGN.md 6번).
        .background(
            DS.Surface.card
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
