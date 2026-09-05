import SwiftUI
import UIKit

/// 농협 항목을 손으로 넣는 화면.
///
/// 농협은 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이 앱 화면을 보고
/// 옮겨 적는 수밖에 없다. 한 달에 25건 안팎을 연달아 넣는다. 그래서 이 화면의
/// 설계 목표는 하나다 — **빠르고 가볍게.**
///
/// **토스 송금 문법 그대로 — 금액 먼저, 단계로 전개한다.**
///   1단계(금액): 화면 위에 큰 금액, 하단에 커스텀 숫자패드. 금액이 들어오면
///      패드 위 **다음**이 켜진다. 패드 좌하단 키는 `00` 대신 **입금/출금 토글**이라,
///      금액 색과 함께 지금 종류가 무엇인지도 보여준다.
///   2단계(적요): 다음을 누르면 적요 칸이 나타나 포커스가 옮겨간다(시스템 키보드).
///      금액은 위에 작은 요약으로 접히고, 눌러서 1단계로 되돌아간다. 날짜는 그 달
///      1일이 기본이라 대개 안 건드린다.
///
/// **통장은 안 묻는다 — 늘 농협이다.** "통장은 입력 경로가 정한다" — 모임통장은
/// 거래내역서로만 들어오고, 손으로 넣는 건 정의상 농협뿐이다. 모임을 손으로 적으면
/// 나중에 내역서에서 같은 게 또 들어와 두 줄이 된다.
///
/// - **저장해도 닫히지 않는다.** 저장하면 금액과 적요만 비우고 1단계로 돌아가
///   그 자리에서 다음 건을 받는다. 날짜·종류는 남는다 (같은 날 여러 건이
///   몰린다 — 8/5 에 7건).
/// - **카테고리를 묻지 않는다.** 목록에서 선택 모드로 훑으며 붙이는 편이 낫다.
/// - 넣은 건수를 제목에 센다.
///
/// **내부 이체 토글은 없다.** 손으로 넣는 건 은행 증명이 없어 거래가 아니라 **항목**
/// 으로 바로 들어간다 (`addManualItem`, `sourceTransactionId == nil`).
struct AddTransactionView: View {
    @ObservedObject var viewModel: FinanceViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var descFocused: Bool

    /// 입력 단계. 금액 → 적요.
    private enum Step { case amount, details }
    @State private var step: Step = .amount

    @State private var datetime: Date
    @State private var isDeposit = false
    /// 금액의 숫자만 (콤마 없이). 커스텀 패드가 이걸 민다.
    @State private var amountDigits = ""
    @State private var descriptionText = ""
    /// 늘 농협이다. 손입력은 정의상 농협뿐이라 고르는 자리를 두지 않는다.
    @State private var accountId: UUID?

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
    private var amountColor: Color { isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal }

    var body: some View {
        NavigationView {
            Form {
                if step == .amount {
                    amountHeroSection
                } else {
                    amountSummarySection
                    Section {
                        TextField("적요 (예: 헌금, 심방비)", text: $descriptionText)
                            .focused($descFocused)
                    }
                    dateSection
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
                    } else if step == .details {
                        Button("저장") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            // 1단계에서만 하단에 커스텀 숫자패드를 고정한다.
            .safeAreaInset(edge: .bottom) {
                if step == .amount {
                    AmountKeypad(
                        isDeposit: $isDeposit,
                        canProceed: magnitude > 0,
                        onNext: goToDetails,
                        onDigit: { d in
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

    /// 1단계 — 금액을 큰 글씨로. 아래 캡션이 종류를 한 단어로 말한다.
    private var amountHeroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.tight) {
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
                Text(isDeposit ? "입금" : "출금")
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.section)
            .listRowBackground(Color.clear)
        }
    }

    /// 2단계 위 금액 요약 — 누르면 1단계로 되돌아간다.
    private var amountSummarySection: some View {
        Section {
            Button {
                descFocused = false
                withAnimation(DS.Motion.control) { step = .amount }
            } label: {
                HStack(spacing: DS.Spacing.tight) {
                    Text("\(magnitude.formatted())원")
                        .typeStyle(DS.Typo.h3)
                        .tabularAmount()
                        .foregroundColor(amountColor)
                    Text(isDeposit ? "입금" : "출금")
                        .typeStyle(DS.Typo.body2)
                        .foregroundColor(DS.Ink.secondary)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(DS.Icon.font(DS.Icon.s))
                        .foregroundColor(DS.Ink.placeholder)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }

    /// 날짜 한 줄. 통장은 안 묻는다(늘 농협). 기기 언어가 영어여도 달력은 한국어로 뜬다.
    private var dateSection: some View {
        Section {
            DatePicker("날짜", selection: $datetime, displayedComponents: [.date])
                .environment(\.locale, Locale(identifier: "ko_KR"))
        } footer: {
            Text("저장해도 안 닫혀요. 날짜·종류는 그대로 남아 다음 건을 바로 넣어요. 손으로 넣는 건 늘 농협이에요 — 모임통장은 거래내역서를 불러오면 자동으로 채워져요.")
        }
    }

    private func goToDetails() {
        guard magnitude > 0 else { return }
        withAnimation(DS.Motion.control) { step = .details }
        // 화면 전환 뒤 적요로 포커스를 옮긴다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { descFocused = true }
    }

    /// 저장하고 **1단계로 돌아가 다음 건을 받는다.** 비우는 건 금액과 적요뿐이다.
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
            descFocused = false
            withAnimation(DS.Motion.control) { step = .amount }
        }
    }
}

/// 토스식 커스텀 숫자패드. 화면 하단에 고정된다 — 열고 닫히는 애니메이션이 없다.
///
/// 위에 **다음**(금액이 들어오면 켜짐), 아래 좌하단 키는 `00` 대신 **입금/출금 토글**
/// 이다 — 눌러서 종류를 바꾸고, 지금 무엇인지도 색으로 보여준다.
private struct AmountKeypad: View {
    @Binding var isDeposit: Bool
    let canProceed: Bool
    let onNext: () -> Void
    let onDigit: (String) -> Void
    let onBackspace: () -> Void

    private enum Key: Hashable { case digit(String), toggle, back }
    private let keys: [Key] = [
        .digit("1"), .digit("2"), .digit("3"),
        .digit("4"), .digit("5"), .digit("6"),
        .digit("7"), .digit("8"), .digit("9"),
        .toggle,     .digit("0"), .back
    ]

    /// 토스처럼 키를 누를 때마다 가벼운 진동을 준다.
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                haptic(.medium)
                onNext()
            } label: {
                Text("다음")
                    .typeStyle(DS.Typo.labelL)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonXL)
                    .foregroundColor(DS.Ink.onAccent)
                    .background(canProceed ? DS.Palette.accent : DS.Palette.accent.opacity(DS.State.disabledOpacity))
            }
            .buttonStyle(.plain)
            .disabled(!canProceed)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                      spacing: DS.Spacing.tight) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        haptic(.medium)
                        switch key {
                        case .digit(let d): onDigit(d)
                        case .toggle: isDeposit.toggle()
                        case .back: onBackspace()
                        }
                    } label: {
                        keyLabel(key)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonXL)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.tight)
        }
        .background(
            DS.Surface.card
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func keyLabel(_ key: Key) -> some View {
        switch key {
        case .digit(let d):
            Text(d).typeStyle(DS.Typo.h3).foregroundColor(DS.Ink.primary)
        case .back:
            Image(systemName: "delete.left")
                .font(DS.Icon.font(DS.Icon.action))
                .foregroundColor(DS.Ink.primary)
        case .toggle:
            // 지금 종류를 색으로 보여주고, 눌러서 바꾼다.
            Text(isDeposit ? "입금" : "출금")
                .typeStyle(DS.Typo.labelM)
                .foregroundColor(isDeposit ? DS.Palette.deposit : DS.Ink.primary)
        }
    }
}
