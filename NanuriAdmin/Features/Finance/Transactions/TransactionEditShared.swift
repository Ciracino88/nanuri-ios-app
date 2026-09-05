import SwiftUI

/// 두 "항목 상세" 화면(`TransactionEditView`·`PieceEditView`)이 함께 쓰는 조각들.
///
/// **화면은 상세다.** 값을 죽 나열하고, 고칠 수 있는 것만 `chevron` 을 달아 눌러서
/// 필드별 시트를 연다. 거래내역서에서 온 값(금액·일시·통장)은 chevron 을 안 달아
/// **같은 레이아웃 그대로 잠긴 것처럼 보인다** — 수기 항목과 화면이 갈리지 않는다.
///
/// 시트는 값을 **로컬로만** 바꾼다. 실제 저장은 상세 화면의 "저장" 이
/// `saveTransactionEdits` 로 한 번에 한다.

// MARK: - 상세 행

/// 상세 화면의 한 줄. `onEdit` 이 있으면 chevron 을 달고 눌러 편집 시트를 연다.
/// 없으면 값만 보여주는 읽기 전용 줄이다.
struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = DS.Ink.primary
    var isPlaceholder: Bool = false
    var onEdit: (() -> Void)?

    var body: some View {
        if let onEdit {
            Button(action: onEdit) {
                LabeledContent(label) {
                    HStack(spacing: DS.Spacing.tight) {
                        Text(value)
                            .foregroundColor(isPlaceholder ? DS.Ink.placeholder : valueColor)
                        Image(systemName: "chevron.right")
                            .font(DS.Icon.font(DS.Icon.m))
                            .foregroundColor(DS.Ink.placeholder)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            LabeledContent(label) {
                Text(value).foregroundColor(valueColor)
            }
        }
    }
}

// MARK: - 금액 히어로

/// **첫 섹션은 금액 하나를 크게 세운다** (토스 결제 결과 화면의 문법).
/// 수는 절댓값으로 두고 입금·출금·이체는 색과 그 아래 한 단어가 말한다.
///
/// `onEdit` 이 있으면(손입력 거래) 히어로 전체가 눌러서 금액을 고치는 버튼이 되고
/// 캡션 옆에 chevron 이 붙는다. 없으면(조각·거래내역서 거래) 읽기 전용이다.
struct AmountHeroSection: View {
    let displayAmount: Int
    let color: Color
    let caption: String
    var onEdit: (() -> Void)?

    var body: some View {
        Section {
            Group {
                if let onEdit {
                    Button(action: onEdit) { heroBody(editable: true) }
                        .buttonStyle(.plain)
                } else {
                    heroBody(editable: false)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.medium)
            .listRowBackground(Color.clear)
        }
    }

    private func heroBody(editable: Bool) -> some View {
        VStack(spacing: DS.Spacing.tight) {
            Text("\(abs(displayAmount).formatted())원")
                .typeStyle(DS.Typo.display2)
                .tabularAmount()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: DS.Spacing.tight) {
                Text(caption)
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.secondary)
                if editable {
                    Image(systemName: "chevron.right")
                        .font(DS.Icon.font(DS.Icon.s))
                        .foregroundColor(DS.Ink.placeholder)
                }
            }
        }
    }
}

// MARK: - 영수증 · 삭제

/// 영수증은 상세에 **버튼 하나**로만 둔다. 있으면 "보기", 없으면 "추가" — 어느 쪽이든
/// 같은 관리 시트(`ReceiptManagerView`)를 연다.
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

// MARK: - 필드별 편집 시트

/// 어느 필드를 편집 중인가. 상세 화면이 `.sheet(item:)` 로 하나만 띄운다.
enum EditField: Int, Identifiable {
    case amount, date, account, description, category
    var id: Int { rawValue }
}

/// 금액 + 입금/출금. 크기와 부호를 한 자리에서 고친다 (부호는 종류가 정한다).
struct AmountEditSheet: View {
    @State private var magnitude: Int
    @State private var isDeposit: Bool
    let onSave: (Int, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    init(magnitude: Int, isDeposit: Bool, onSave: @escaping (Int, Bool) -> Void) {
        _magnitude = State(initialValue: magnitude)
        _isDeposit = State(initialValue: isDeposit)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("금액") {
                    TextField("금액", value: $magnitude, format: .number)
                        .keyboardType(.numberPad)
                }
                Section("종류") {
                    Picker("종류", selection: $isDeposit) {
                        Text("입금").tag(true)
                        Text("출금").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("금액")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar(dismiss: dismiss) { onSave(magnitude, isDeposit) } }
            .presentationDetents([.medium])
        }
    }
}

/// 일시.
struct DateEditSheet: View {
    @State private var date: Date
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    init(date: Date, onSave: @escaping (Date) -> Void) {
        _date = State(initialValue: date)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                DatePicker("일시", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("일시")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar(dismiss: dismiss) { onSave(date) } }
            .presentationDetents([.medium, .large])
        }
    }
}

/// 통장 고르기 (통장·상대 통장 공용). `choices` 만 바꿔 넘긴다.
struct AccountEditSheet: View {
    let title: String
    let choices: [Account]
    @State private var selected: UUID
    let onSave: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, choices: [Account], selected: UUID, onSave: @escaping (UUID) -> Void) {
        self.title = title
        self.choices = choices
        _selected = State(initialValue: selected)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Picker(title, selection: $selected) {
                    ForEach(choices) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar(dismiss: dismiss) { onSave(selected) } }
            .presentationDetents([.medium])
        }
    }
}

/// 적요 (자유 텍스트).
struct DescriptionEditSheet: View {
    @State private var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(text: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("적요 (예: 아침식사, 8월 헌금)", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("장부에 적힐 이름이에요. 비워 두면 은행 적요가 그대로 남아요.")
                }
            }
            .navigationTitle("적요")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar(dismiss: dismiss) { onSave(text) } }
            .presentationDetents([.medium])
        }
    }
}

/// 카테고리 (자유 텍스트 + 자주 쓰는 값 칩).
struct CategoryEditSheet: View {
    @State private var text: String
    let suggestions: [String]
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(text: String, suggestions: [String], onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.suggestions = suggestions
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $text)
                    CategorySuggestionChips(suggestions: suggestions, selected: $text)
                } footer: {
                    Text("성격에 맞게 묶는 꼬리표예요. 합계·보고서가 이걸로 묶어요.")
                }
            }
            .navigationTitle("카테고리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar(dismiss: dismiss) { onSave(text) } }
            .presentationDetents([.medium, .large])
        }
    }
}

/// 편집 시트 공통 툴바 — 취소 / 완료. **완료는 로컬 반영일 뿐, DB 저장은 상세의 "저장".**
@ToolbarContentBuilder
private func editToolbar(dismiss: DismissAction, onDone: @escaping () -> Void) -> some ToolbarContent {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("취소") { dismiss() }
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Button("완료") { onDone(); dismiss() }.fontWeight(.semibold)
    }
}
