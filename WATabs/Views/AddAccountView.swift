import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Название вкладки") {
                    TextField("Например, Склад", text: $name)
                }
                Section("Цвет") {
                    SwatchPicker(selection: $colorHex)
                }
                Section {
                    Text("После добавления откроется QR-код. На телефоне с этим номером: WhatsApp Business → Связанные устройства → Привязка устройства → наведи камеру на QR.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новый аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        store.add(name: name.trimmingCharacters(in: .whitespaces), colorHex: colorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if colorHex.isEmpty { colorHex = store.nextColor } }
        }
    }
}

/// Ряд цветных кружков из палитры.
struct SwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccountStore.palette, id: \.self) { hex in
                Circle().fill(Color(hex: hex))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.primary, lineWidth: selection == hex ? 2 : 0).padding(-4))
                    .onTapGesture { selection = hex }
            }
        }
        .padding(.vertical, 6)
    }
}
