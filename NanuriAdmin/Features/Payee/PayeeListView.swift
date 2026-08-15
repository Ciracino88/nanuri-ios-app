import SwiftUI

/// 계좌부 관리 화면.
/// 청구 폼이 이름만 받으므로, 여기에 등록된 이름과 대조해 송금 계좌를 찾는다.
struct PayeeListView: View {
    @ObservedObject var viewModel: PayeeViewModel
    /// 계좌 미등록 청구서에서 바로 넘어왔을 때 이름을 미리 채워준다.
    var prefilledName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var editing: PayeeEditTarget?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.payees.isEmpty {
                    ProgressView()
                } else if viewModel.payees.isEmpty {
                    VStack(spacing: 8) {
                        Text("등록된 계좌가 없어요")
                            .foregroundColor(.gray)
                        Text("청구자 이름과 계좌를 미리 등록해 두면\n청구서가 들어올 때 자동으로 연결돼요.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        ForEach(viewModel.payees) { payee in
                            Button {
                                editing = .edit(payee)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(payee.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(payee.accountLine)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let memo = payee.memo, !memo.isEmpty {
                                        Text(memo)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { viewModel.payees[$0].id }
                            Task { for id in ids { await viewModel.delete(id: id) } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("계좌부")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editing = .create(prefilledName ?? "")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { target in
                PayeeEditView(viewModel: viewModel, target: target)
            }
        }
        .task {
            await viewModel.fetchPayees()
            // 계좌 미등록 청구서에서 넘어왔으면 바로 등록 시트를 띄운다.
            if let prefilledName, viewModel.payee(for: prefilledName) == nil {
                editing = .create(prefilledName)
            }
        }
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
