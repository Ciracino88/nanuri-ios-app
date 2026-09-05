import SwiftUI
import UIKit

/// 농협 항목을 손으로 넣는 **풀스크린** 화면. 토스 송금 화면의 문법을 따른다.
///
/// 농협은 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이 앱 화면을 보고
/// 옮겨 적는 수밖에 없다. 한 달에 25건 안팎을 연달아 넣는다. 그래서 이 화면의
/// 설계 목표는 하나다 — **빠르고 가볍게.**
///
/// **위에서 아래로 날짜 → 적요 → 금액**, 금액은 맨 아래 큰 글씨로 앉고 그 밑에
/// 커스텀 숫자패드가 붙는다. 날짜는 재정 탭과 같은 가로 주 셀렉터(`WeekDatePicker`)로
/// 고른다.
///
/// **흐름:** 열면 적요에 포커스가 가고(시스템 키보드), 적요에서 **엔터를 치면 커스텀
/// 숫자패드가 뜨며 금액으로 포커스가 옮겨간다.** 금액을 다 넣으면 하단 **저장** CTA 로
/// 확정한다. 취소는 좌상단 뒤로(‹).
///
/// **통장은 안 묻는다 — 늘 농협이다.** "통장은 입력 경로가 정한다." 모임통장은
/// 거래내역서로만 들어오고, 손으로 넣는 건 정의상 농협뿐이다.
///
/// - **저장해도 닫히지 않는다.** 금액·적요만 비우고 다시 적요 포커스로 돌아가 그
///   자리에서 다음 건을 받는다. 날짜·종류는 남는다 (같은 날 여러 건이 몰린다).
/// - **카테고리를 묻지 않는다.** 목록에서 선택 모드로 훑으며 붙이는 편이 낫다.
///
/// 손으로 넣는 건 은행 증명이 없어 거래가 아니라 **항목**으로 바로 들어간다
/// (`addManualItem`, `sourceTransactionId == nil`).
struct AddTransactionView: View {
    @ObservedObject var viewModel: FinanceViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var descFocused: Bool

    @State private var datetime: Date
    @State private var isDeposit = false
    /// 금액의 숫자만 (콤마 없이). 커스텀 패드가 이걸 민다.
    @State private var amountDigits = ""
    /// 금액을 입력 중인가 — 켜지면 커스텀 숫자패드가 뜬다.
    @State private var amountActive = false
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
        NavigationStack {
            VStack(spacing: 0) {
                // 날짜 셀렉터는 헤더에 밀착한다.
                WeekDatePicker(viewModel: viewModel, selection: $datetime)

                // 적요 — 라벨 없이 문구로, 좌측 정렬. 날짜와는 여백으로 가른다.
                descriptionField
                    .padding(.top, DS.Spacing.s8)
                    .padding(.horizontal, DS.Spacing.screen)

                // 금액 — 적요 바로 아래, 좌측 정렬. 라벨 없이 수만 세운다.
                Button { activateAmount() } label: {
                    VStack(alignment: .leading, spacing: DS.Spacing.tight) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Spacing.section)
                .padding(.horizontal, DS.Spacing.screen)

                // 빈 공간은 금액 아래로. 그래야 적요·금액이 붙어 있는다.
                Spacer(minLength: 0)
            }
            .screenBackground(DS.Surface.card)
            .navigationTitle(savedCount == 0 ? "거래 추가" : "거래 추가 (\(savedCount)건)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 취소 = 뒤로가기(‹).
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            // 금액을 넣는 중에만 하단에 커스텀 숫자패드 + 저장 CTA 를 고정한다.
            .safeAreaInset(edge: .bottom) {
                if amountActive {
                    AmountKeypad(
                        isDeposit: $isDeposit,
                        ctaTitle: "저장",
                        ctaEnabled: canSave,
                        onCTA: save,
                        onDigit: { d in
                            guard amountDigits.count < 9 else { return }
                            if amountDigits.isEmpty && (d == "0" || d == "00") { return }
                            amountDigits += d
                        },
                        onBackspace: { amountDigits = String(amountDigits.dropLast()) }
                    )
                }
            }
            .onAppear {
                // 처음 포커스는 적요.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { descFocused = true }
            }
            .onChange(of: descFocused) { _, focused in
                // 적요로 돌아가면 숫자패드를 걷는다.
                if focused { amountActive = false }
            }
        }
    }

    /// 적요 — 라벨 없이 가운데 문구로. 비면 "적요를 입력해주세요", 들어오면 뒤에
    /// 조사가 붙어 "헌금으로"·"심방비로" 처럼 문장으로 읽힌다.
    private var descriptionField: some View {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: DS.Spacing.s1) {
            TextField("적요를 입력해주세요", text: $descriptionText)
                .typeStyle(DS.Typo.h4)
                .multilineTextAlignment(.leading)
                .fixedSize()
                .focused($descFocused)
                .submitLabel(.next)
                .onSubmit { activateAmount() }
            if !trimmed.isEmpty {
                Text(objectParticle(trimmed))
                    .typeStyle(DS.Typo.h4)
                    .foregroundColor(DS.Ink.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 목적격 조사 "으로/로". 받침이 없거나 ㄹ 이면 "로", 그 밖엔 "으로".
    /// 한글 음절이 아니면(숫자·영문) 기본값 "으로".
    private func objectParticle(_ text: String) -> String {
        guard let scalar = text.unicodeScalars.last, (0xAC00...0xD7A3).contains(scalar.value) else {
            return "으로"
        }
        let jongseong = (Int(scalar.value) - 0xAC00) % 28
        return (jongseong == 0 || jongseong == 8) ? "로" : "으로"
    }

    /// 적요 키보드를 내리고 숫자패드를 띄우며 금액으로 포커스를 옮긴다.
    private func activateAmount() {
        descFocused = false
        withAnimation(DS.Motion.control) { amountActive = true }
    }

    /// 저장하고 **적요 포커스로 돌아가 다음 건을 받는다.** 비우는 건 금액과 적요뿐이다.
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
            amountActive = false
            descFocused = true
        }
    }
}

/// 토스식 커스텀 숫자패드. 화면 하단에 고정된다 — 열고 닫히는 애니메이션이 없다.
///
/// 위에 **CTA**(저장 등), 아래 좌하단 키는 `00` 대신 **입금/출금 토글**이다 — 눌러서
/// 종류를 바꾸고, 지금 무엇인지도 색으로 보여준다. 키마다 가벼운 진동을 준다.
private struct AmountKeypad: View {
    @Binding var isDeposit: Bool
    let ctaTitle: String
    let ctaEnabled: Bool
    let onCTA: () -> Void
    let onDigit: (String) -> Void
    let onBackspace: () -> Void

    private enum Key: Hashable { case digit(String), toggle, back }
    private let keys: [Key] = [
        .digit("1"), .digit("2"), .digit("3"),
        .digit("4"), .digit("5"), .digit("6"),
        .digit("7"), .digit("8"), .digit("9"),
        .toggle,     .digit("0"), .back
    ]

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    var body: some View {
        VStack(spacing: 0) {
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

            // 하단 CTA — 저장.
            Button {
                haptic(.medium)
                onCTA()
            } label: {
                Text(ctaTitle)
                    .typeStyle(DS.Typo.labelL)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonXL)
                    .foregroundColor(DS.Ink.onAccent)
                    .background(ctaEnabled ? DS.Palette.accent : DS.Palette.accent.opacity(DS.State.disabledOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
            }
            .buttonStyle(.plain)
            .disabled(!ctaEnabled)
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.bottom, DS.Spacing.small)
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
            Text(isDeposit ? "입금" : "출금")
                .typeStyle(DS.Typo.labelM)
                .foregroundColor(isDeposit ? DS.Palette.deposit : DS.Ink.primary)
        }
    }
}
