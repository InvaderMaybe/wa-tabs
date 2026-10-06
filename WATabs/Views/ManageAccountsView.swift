import SwiftUI

struct ManageAccountsView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var pool: WebViewPool
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: Double = 1.0
    @State private var scriptStatus: String?
    @State private var background = BackgroundKeeper.shared.enabled

    var body: some View {
        NavigationStack {
            List {
                Section("Порядок вкладок") {
                    ForEach(store.accounts) { account in
                        NavigationLink {
                            EditAccountView(account: account)
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(account.color).frame(width: 28, height: 28)
                                    .overlay(Text(account.initials).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                                Text(account.name)
                            }
                        }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }

                Section("Вид") {
                    VStack(alignment: .leading) {
                        Text("Масштаб WhatsApp: \(Int(zoom * 100))%")
                        Slider(value: $zoom, in: 0.6...1.4, step: 0.05) { editing in
                            if !editing { pool.zoom = zoom }
                        }
                    }
                }

                Section {
                    Toggle("Работать в фоне", isOn: $background)
                        .onChange(of: background) { _, on in BackgroundKeeper.shared.enabled = on }
                } header: {
                    Text("Уведомления и звонки")
                } footer: {
                    Text("Нужно, чтобы приходили уведомления о сообщениях и входящие звонки, когда приложение свёрнуто. Расходует батарею примерно как музыка в фоне.")
                }

                Section("Подпись приложения") {
                    Text(ProvisionInfo.statusText)
                    Text("Продлевается SideStore автоматически.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Обёртка WhatsApp") {
                    LabeledContent("Версия скрипта", value: "v\(ScriptProvider.shared.version)")
                    Button("Проверить обновление") {
                        Task {
                            let updated = await ScriptProvider.shared.refreshFromRemote()
                            if updated { pool.reinjectScript() }
                            scriptStatus = updated ? "Обновлено до v\(ScriptProvider.shared.version)" : "Уже последняя версия"
                        }
                    }
                    if let scriptStatus {
                        Text(scriptStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Управление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .onAppear { zoom = pool.zoom }
        }
    }
}

private struct EditAccountView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var pool: WebViewPool
    @Environment(\.dismiss) private var dismiss

    @State var account: Account
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Название") {
                TextField("Название", text: $account.name)
            }
            Section("Цвет") {
                SwatchPicker(selection: $account.colorHex)
            }
            Section {
                Button("Перезагрузить WhatsApp") { pool.reload(account.id) }
                Button("Выйти и удалить аккаунт", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Удаление стирает вход и данные этой вкладки. На телефоне устройство тоже стоит отвязать.")
            }
        }
        .navigationTitle(account.name)
        .onDisappear {
            if store.accounts.contains(where: { $0.id == account.id }), !account.name.trimmingCharacters(in: .whitespaces).isEmpty {
                store.update(account)
            }
        }
        .confirmationDialog("Удалить «\(account.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                let id = account.id
                store.remove(id)
                Task { await pool.remove(id) }
                dismiss()
            }
        }
    }
}
