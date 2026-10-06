import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var pool: WebViewPool

    @State private var drawerOpen = false
    @State private var showAdd = false
    @State private var showManage = false

    private var currentInChat: Bool {
        guard let id = store.selectedID else { return false }
        return pool.inChat[id] ?? false
    }

    var body: some View {
        ZStack {
            if store.accounts.isEmpty {
                EmptyStateView { showAdd = true }
            } else {
                VStack(spacing: 0) {
                    TopBar(inChat: currentInChat,
                           onMenu: { withAnimation(.easeOut(duration: 0.22)) { drawerOpen = true } },
                           onBack: { if let id = store.selectedID { pool.back(id) } })
                    WebStack(ids: store.accounts.map(\.id), selected: store.selectedID, pool: pool) {
                        if currentInChat, let id = store.selectedID {
                            pool.back(id)
                        } else {
                            withAnimation(.easeOut(duration: 0.22)) { drawerOpen = true }
                        }
                    }
                }
            }

            DrawerView(isOpen: $drawerOpen,
                       onAdd: { drawerOpen = false; showAdd = true },
                       onManage: { drawerOpen = false; showManage = true })
        }
        .sheet(isPresented: $showAdd) { AddAccountView() }
        .sheet(isPresented: $showManage) { ManageAccountsView() }
        .onAppear { pool.sync(store.accounts) }
        .onChange(of: store.accounts) { _, accounts in pool.sync(accounts) }
    }
}

/// Плашка сверху: ☰ / ‹, текущий аккаунт, непрочитанные в остальных.
private struct TopBar: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var pool: WebViewPool
    let inChat: Bool
    let onMenu: () -> Void
    let onBack: () -> Void

    private var othersUnread: Int {
        pool.unread.filter { $0.key != store.selectedID }.values.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: inChat ? onBack : onMenu) {
                Image(systemName: inChat ? "chevron.left" : "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .contentTransition(.symbolEffect(.replace))

            if let account = store.selected {
                Button(action: onMenu) {
                    HStack(spacing: 8) {
                        Circle().fill(account.color).frame(width: 9, height: 9)
                        Text(account.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            if othersUnread > 0 {
                Button(action: onMenu) {
                    HStack(spacing: 4) {
                        Text("ещё").foregroundStyle(.secondary)
                        Badge(count: othersUnread, color: .red)
                    }
                    .font(.system(size: 13))
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct Badge: View {
    let count: Int
    var color: Color = Color(hex: "25D366")

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(color))
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "25D366"))
            Text("Нет аккаунтов").font(.title2.bold())
            Text("Добавь первый WhatsApp и привяжи его по QR-коду.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Добавить аккаунт", action: onAdd)
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "25D366"))
        }
        .padding(32)
    }
}
