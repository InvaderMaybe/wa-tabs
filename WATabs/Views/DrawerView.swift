import SwiftUI

/// Боковая шторка с аккаунтами (вариант C).
struct DrawerView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var pool: WebViewPool
    @Binding var isOpen: Bool
    let onAdd: () -> Void
    let onManage: () -> Void

    @GestureState private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.82, 340)
            ZStack(alignment: .leading) {
                Color.black.opacity(isOpen ? 0.35 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { close() }

                panel
                    .frame(width: width)
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .shadow(color: .black.opacity(isOpen ? 0.25 : 0), radius: 16, x: 4)
                    .offset(x: isOpen ? min(0, dragX) : -width - 20)
                    .gesture(
                        DragGesture()
                            .updating($dragX) { value, state, _ in state = value.translation.width }
                            .onEnded { value in if value.translation.width < -80 { close() } }
                    )
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Аккаунты")
                .font(.title3.bold())
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if let warning = ProvisionInfo.expiryWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.accounts) { account in
                        row(account)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onAdd) { Label("Добавить аккаунт", systemImage: "plus") }
                    .padding(.vertical, 8)
                Button(action: onManage) { Label("Управление", systemImage: "gearshape") }
                    .padding(.vertical, 8)
            }
            .font(.system(size: 15))
            .tint(Color(hex: "128C7E"))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func row(_ account: Account) -> some View {
        let selected = account.id == store.selectedID
        let unread = pool.unread[account.id] ?? 0
        return Button {
            store.select(account.id)
            close()
        } label: {
            HStack(spacing: 12) {
                Circle().fill(account.color)
                    .frame(width: 40, height: 40)
                    .overlay(Text(account.initials).font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(unread > 0 ? "Непрочитанных: \(unread)" : "Нет новых")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if unread > 0 { Badge(count: unread) }
            }
            .padding(.vertical, 10)
            .padding(.leading, selected ? 13 : 16)
            .padding(.trailing, 16)
            .background(selected ? Color(.secondarySystemBackground) : .clear)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(Color(hex: "25D366")).frame(width: 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
    }
}
