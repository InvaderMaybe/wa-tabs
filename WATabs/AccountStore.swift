import SwiftUI

struct Account: Identifiable, Codable, Equatable {
    var id: UUID = UUID()          // он же идентификатор WKWebsiteDataStore
    var name: String
    var colorHex: String

    var color: Color { Color(hex: colorHex) }
    var initials: String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2)).uppercased()
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var selectedID: UUID?

    private let key = "accounts.v1"
    private let selectedKey = "accounts.selected"

    static let palette = ["25D366", "34B7F1", "F5A623", "E94F64", "9B59B6", "1ABC9C", "F06292", "607D8B"]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        if let raw = UserDefaults.standard.string(forKey: selectedKey), let id = UUID(uuidString: raw),
           accounts.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = accounts.first?.id
        }
    }

    var selected: Account? { accounts.first { $0.id == selectedID } }

    func select(_ id: UUID) {
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
    }

    func add(name: String, colorHex: String) {
        let account = Account(name: name, colorHex: colorHex)
        accounts.append(account)
        save()
        select(account.id)
    }

    func update(_ account: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i] = account
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
        if selectedID == id {
            if let first = accounts.first { select(first.id) } else { selectedID = nil }
        }
    }

    var nextColor: String { Self.palette[accounts.count % Self.palette.count] }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0x25D366
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
