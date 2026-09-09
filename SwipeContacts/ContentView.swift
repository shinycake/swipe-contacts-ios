import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(ICloudStore.self) private var store
    @State private var tab: Tab = .deck

    enum Tab: String {
        case deck, kept, trash, stars
    }

    var body: some View {
        Group {
            switch store.phase {
            case .boot:
                ProgressView().tint(.white)
            case .needAccess:
                Gate(
                    title: "Keep or toss.",
                    bodyText: "Swipe your iCloud contacts. Right keeps a group that syncs to every Apple device. Left deletes on iCloud everywhere.",
                    cta: "Allow Contacts"
                ) { Task { await store.requestAccess() } }
            case .denied:
                Gate(
                    title: "Contacts locked",
                    bodyText: "Enable Contacts for Swipe Contacts in Settings → Privacy & Security → Contacts.",
                    cta: nil,
                    action: nil
                )
            case .noICloud:
                Gate(
                    title: "No iCloud Contacts",
                    bodyText: "On this iPhone: Settings → [your name] → iCloud → Contacts → on. Then reopen the app.",
                    cta: "Try again",
                    action: { store.load() }
                )
            case .ready:
                ready
            }
        }
        .background(Color(red: 0.047, green: 0.047, blue: 0.055).ignoresSafeArea())
    }

    private var ready: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                switch tab {
                case .deck:
                    DeckScreen()
                case .kept:
                    ListsScreen(title: "Kept", items: store.kept, actionTitle: "Unkeep") { store.unkeep($0) }
                case .trash:
                    ListsScreen(title: "Trash", items: store.trash, actionTitle: "Restore") { store.restore($0) }
                case .stars:
                    ListsScreen(title: "Stars", items: store.starred, actionTitle: nil, action: nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if tab == .deck {
                actionBar
            }

            navBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if tab == .deck {
                Text(store.accountLabel.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.78))
            }
            Text(headerTitle)
                .font(.system(size: tab == .deck ? 28 : 22, weight: .bold))
                .foregroundStyle(Color(white: 0.9))
            if tab == .deck {
                Text("Right keep · Left delete · Syncs everywhere")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.78))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var headerTitle: String {
        switch tab {
        case .deck: return store.deck.isEmpty ? "Done" : "\(store.deck.count) left"
        case .kept: return "Kept"
        case .trash: return "Trash"
        case .stars: return "Stars"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            CircleBtn(system: "xmark", color: Color(red: 1, green: 0.23, blue: 0.19)) {
                if let c = store.deck.first { store.delete(c) }
            }
            CircleBtn(system: "arrow.uturn.backward", color: Color(white: 0.9)) {
                store.undoLast()
            }
            CircleBtn(
                system: (store.deck.first?.starred == true) ? "star.fill" : "star",
                color: Color(red: 1, green: 0.84, blue: 0.04)
            ) {
                if let c = store.deck.first { store.toggleStar(c) }
            }
            CircleBtn(system: "heart.fill", color: Color(red: 0.20, green: 0.78, blue: 0.35)) {
                if let c = store.deck.first { store.keep(c) }
            }
        }
        .padding(.vertical, 8)
    }

    private var navBar: some View {
        HStack(spacing: 0) {
            NavItem(system: "person.2.fill", label: "Deck", selected: tab == .deck) { tab = .deck }
            NavItem(system: "bookmark.fill", label: "Kept", selected: tab == .kept) { tab = .kept }
            NavItem(system: "trash.fill", label: "Trash", selected: tab == .trash) { tab = .trash }
            NavItem(system: "star.fill", label: "Stars", selected: tab == .stars) { tab = .stars }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(red: 0.08, green: 0.08, blue: 0.086))
    }
}

private struct CircleBtn: View {
    let system: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 56, height: 56)
                .background(Color(white: 0.17))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct NavItem: View {
    let system: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(selected ? Color(white: 0.23) : Color.clear)
                        .frame(width: 64, height: 32)
                    Image(systemName: system)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? Color(white: 0.9) : Color(white: 0.78))
                }
                Text(label)
                    .font(.system(size: 12, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? Color(white: 0.9) : Color(white: 0.78))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct Gate: View {
    let title: String
    let bodyText: String
    let cta: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(white: 0.9))
            Text(bodyText)
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.78))
            if let cta, let action {
                Button(cta, action: action)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 10)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct DeckScreen: View {
    @Environment(ICloudStore.self) private var store

    var body: some View {
        ZStack {
            if store.deck.isEmpty {
                VStack(spacing: 8) {
                    Text("Inbox zero.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(white: 0.9))
                    Text("Kept contacts are in the iCloud group “Swipe Kept”. Deletes go to iCloud Recently Deleted.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(28)
            } else {
                ZStack {
                    if store.deck.count > 1 {
                        SwipeCard(contact: store.deck[1], offset: .zero, interactive: false)
                            .scaleEffect(0.96)
                            .offset(y: 12)
                            .opacity(0.72)
                    }
                    SwipeCard(
                        contact: store.deck[0],
                        offset: .zero,
                        interactive: true,
                        onKeep: { if let c = store.deck.first { store.keep(c) } },
                        onDelete: { if let c = store.deck.first { store.delete(c) } }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }
}

struct SwipeCard: View {
    let contact: ContactRecord
    var offset: CGSize = .zero
    var interactive: Bool
    var onKeep: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = interactive ? drag : offset
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(avatarColor)
            if let img = contact.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contact.displayName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if contact.starred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.04))
                    }
                }
                if !contact.organization.isEmpty {
                    Text(contact.organization).foregroundStyle(Color(white: 0.75)).font(.system(size: 15))
                }
                if let p = contact.phones.first {
                    Text(p).foregroundStyle(Color(white: 0.75)).font(.system(size: 15))
                }
                if let e = contact.emails.first {
                    Text(e).foregroundStyle(Color(white: 0.75)).font(.system(size: 15))
                }
            }
            .padding(18)

            Text("KEEP")
                .font(.system(size: 26, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.20, green: 0.78, blue: 0.35), lineWidth: 4))
                .rotationEffect(.degrees(-18))
                .opacity(Double(min(1, max(0, t.width / 110))))
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("DELETE")
                .font(.system(size: 26, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 1, green: 0.23, blue: 0.19), lineWidth: 4))
                .rotationEffect(.degrees(18))
                .opacity(Double(min(1, max(0, -t.width / 110))))
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .offset(t)
        .rotationEffect(.degrees(interactive ? t.width / 18 : 0))
        .gesture(interactive ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.translation.width > 110 {
                    fly(1, onKeep)
                } else if value.translation.width < -110 {
                    fly(-1, onDelete)
                } else if reduceMotion {
                    drag = .zero
                } else {
                    withAnimation(.spring(duration: 0.22, bounce: 0)) { drag = .zero }
                }
            }
    }

    private func fly(_ dir: CGFloat, _ done: @escaping () -> Void) {
        let spring = Animation.spring(duration: 0.22, bounce: 0)
        if reduceMotion {
            done()
            drag = .zero
            return
        }
        withAnimation(spring) {
            drag = CGSize(width: dir * 900, height: -40)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            done()
            drag = .zero
        }
    }

    private var avatarColor: Color {
        var h: UInt64 = 0
        for u in contact.displayName.utf8 { h = h &* 31 &+ UInt64(u) }
        return Color(hue: Double(h % 360) / 360, saturation: 0.42, brightness: 0.38)
    }
}

struct ListsScreen: View {
    @Environment(ICloudStore.self) private var store
    let title: String
    let items: [ContactRecord]
    let actionTitle: String?
    let action: ((ContactRecord) -> Void)?

    var body: some View {
        if items.isEmpty {
            Text("Nothing here")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(white: 0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(items) { c in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color(white: 0.17))
                            Text(c.initials)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.displayName).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(white: 0.9))
                            if !c.subtitle.isEmpty {
                                Text(c.subtitle).font(.system(size: 13)).foregroundStyle(Color(white: 0.78))
                            }
                        }
                        Spacer()
                        if let actionTitle, let action {
                            Button(actionTitle) { action(c) }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(white: 0.9))
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(Color(white: 0.17))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color.white.opacity(0.08))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}
