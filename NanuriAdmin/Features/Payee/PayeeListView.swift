import SwiftUI

/// 계좌부 탭.
///
/// 청구 폼은 이름만 받는다. 여기 등록해 둔 이름과 대조해서 송금 계좌를 찾으므로,
/// 이 화면이 비어 있으면 청구서는 들어와도 송금을 못 한다.
struct PayeeListView: View {
    @ObservedObject var viewModel: PayeeViewModel

    @State private var editing: PayeeEditTarget?
    @State private var deleteTarget: Payee?
    @State private var query = ""

    /// 검색어로 거른 목록. 이름·은행·계좌번호 어느 쪽으로도 찾을 수 있다.
    /// 대조는 이름 매칭과 같은 정규화를 쓴다 (공백·대소문자 무시).
    private var filtered: [Payee] {
        let keyword = query.normalizedName
        guard !keyword.isEmpty else { return viewModel.payees }
        return viewModel.payees.filter {
            $0.name.normalizedName.contains(keyword)
                || $0.accountLine.normalizedName.contains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AdminHeaderView(title: "계좌부", trailing: {
                HeaderIconButton(systemName: "plus", label: "계좌 추가") {
                    editing = .create("")
                }
            })

            Group {
                if viewModel.isLoading && viewModel.payees.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.payees.isEmpty {
                    EmptyStateView(
                        title: "등록된 계좌가 없어요",
                        icon: "person.text.rectangle",
                        message: "청구자 이름과 계좌를 미리 등록해 두면\n청구서가 들어올 때 자동으로 연결돼요."
                    )
                    .pullToRefresh { await viewModel.fetchPayees(showLoading: false) }
                } else {
                    list
                }
            }
        }
        .screenBackground()
        .sheet(item: $editing) { target in
            PayeeEditView(viewModel: viewModel, target: target)
        }
        .alert("계좌를 삭제할까요?", isPresented: deleteAlertBinding, presenting: deleteTarget) { payee in
            Button("삭제", role: .destructive) {
                Task { await viewModel.delete(id: payee.id) }
            }
            Button("취소", role: .cancel) {}
        } message: { payee in
            Text("\(payee.name) · \(payee.accountLine)\n청구서에서 이 이름은 다시 '계좌 미등록'으로 표시돼요.")
        }
        .alert("오류", isPresented: .constant(viewModel.error != nil)) {
            Button("확인") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .task {
            await viewModel.fetchPayees()
        }
    }

    /// **검색 줄이 목록 안에 있다.**
    ///
    /// 예전에는 헤더 아래에 붙박여 있어서 목록만 좁은 창처럼 스크롤됐다.
    /// `List` 의 첫 행으로 넣으면 화면 전체가 한 덩어리로 굴러가면서도
    /// **행 스와이프 삭제가 그대로 살아 있다** — `ScrollView` 로 갈아엎었다면
    /// 삭제로 가는 길이 길게 누르기 하나만 남았을 것이다.
    private var list: some View {
        List {
            SearchField(prompt: "이름 · 은행 · 계좌번호", text: $query)
                .padding(.horizontal, DS.Spacing.s4)
                .padding(.vertical, DS.Spacing.medium)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if filtered.isEmpty {
                EmptyStateView(
                    title: "찾는 계좌가 없어요",
                    icon: "magnifyingglass",
                    message: "이름·은행·계좌번호로 찾을 수 있어요."
                )
                .padding(.top, DS.Spacing.s12)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(filtered) { payee in
                row(payee)
                    .cardRow()
                    .onTapGesture { editing = .edit(payee) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTarget = payee
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = payee.accountNumber
                        } label: {
                            Label("계좌번호 복사", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            deleteTarget = payee
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .screenBackground()
        .animation(DS.Motion.list, value: filtered)
        .refreshable {
            await viewModel.fetchPayees(showLoading: false)
        }
    }

    private func row(_ payee: Payee) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(payee.name)
                    .rowTitle()
                Text(payee.accountLine)
                    .rowSubtext()
                if let memo = payee.memo, !memo.isEmpty {
                    Text(memo)
                        .rowSubtext()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(DS.Icon.font(DS.Icon.m))
                .foregroundColor(DS.Ink.placeholder)
        }
        .contentShape(Rectangle())
        .cardStyle()
    }

    /// 알림을 닫을 때 대상도 같이 비운다. `presenting:` 은 대상이 남아 있으면 다시 뜬다.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }
}

enum PayeeEditTarget: Identifiable {
    case create(String)
    case edit(Payee)

    var id: String {
        switch self {
        case .create(let name): return "create-\(name)"
        case .edit(let payee): return "edit-\(payee.id.uuidString)"
        }
    }
}

struct PayeeEditView: View {
    @ObservedObject var viewModel: PayeeViewModel
    let target: PayeeEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var memo = ""
    @State private var isSaving = false

    private var editingId: UUID? {
        if case .edit(let payee) = target { return payee.id }
        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !bankName.isEmpty
            && !accountNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("이름", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("이름")
                } footer: {
                    Text("청구 폼에 적는 이름과 같아야 해요. 띄어쓰기는 달라도 괜찮아요.")
                }

                Section("계좌") {
                    Picker("은행", selection: $bankName) {
                        Text("선택").tag("")
                        ForEach(koreanBanks, id: \.self) { bank in
                            Text(bank).tag(bank)
                        }
                    }
                    TextField("계좌번호", text: $accountNumber)
                        .keyboardType(.numbersAndPunctuation)
                }

                Section("메모") {
                    TextField("선택 사항", text: $memo, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(editingId == nil ? "계좌 추가" : "계좌 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            switch target {
            case .create(let prefilled):
                name = prefilled
            case .edit(let payee):
                name = payee.name
                bankName = payee.bankName
                accountNumber = payee.accountNumber
                memo = payee.memo ?? ""
            }
        }
    }

    private func save() {
        isSaving = true
        let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
        let upsert = PayeeUpsert(
            name: name.whitespaceNormalized,
            bankName: bankName,
            accountNumber: accountNumber.trimmingCharacters(in: .whitespaces),
            memo: trimmedMemo.isEmpty ? nil : trimmedMemo
        )
        Task {
            let ok = await viewModel.save(upsert, id: editingId)
            isSaving = false
            if ok { dismiss() }
        }
    }
}
