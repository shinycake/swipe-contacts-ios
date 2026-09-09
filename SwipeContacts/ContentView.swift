import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(ICloudStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: AppTab = .review

    enum AppTab: Hashable { case review, kept, deleted, favorites }

    var body: some View {
        Group {
            switch store.phase {
            case .boot:
                ProgressView("Loading contacts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needAccess:
                PermissionScreen(symbol: "person.crop.circle.badge.checkmark", title: "Your contacts, in order", message: "Review the contacts you choose to share. Keep favorites organized and remove old entries with a swipe.", buttonTitle: "Continue") {
                    Task { await store.requestAccess() }
                }
            case .denied:
                PermissionScreen(symbol: "person.crop.circle.badge.exclamationmark", title: "Contacts access is off", message: "Allow contact access in Settings to review your address book.", buttonTitle: "Open Settings", action: openSettings)
            case .failed:
                PermissionScreen(symbol: "exclamationmark.icloud", title: "Couldn’t load contacts", message: store.loadError, buttonTitle: "Try Again") {
                    Task { await store.bootstrap() }
                }
            case .ready:
                tabContent
            }
        }
        .background(AppBackground())
        .alert("Contacts", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Review", systemImage: "rectangle.stack.fill", value: .review) { ReviewScreen(openSettings: openSettings) }
                Tab("Kept", systemImage: "bookmark.fill", value: .kept) {
                    ContactListScreen(title: "Kept", emptyTitle: "No kept contacts", emptyMessage: "Swipe right on a contact to keep it here.", symbol: "bookmark", items: store.kept, actionTitle: "Remove", action: store.unkeep)
                }
                Tab("Deleted", systemImage: "trash.fill", value: .deleted) {
                    ContactListScreen(title: "Deleted", emptyTitle: "No deleted contacts", emptyMessage: "Contacts deleted during this session appear here.", symbol: "trash", items: store.trash, actionTitle: "Restore", action: store.restore)
                }
                Tab("Favorites", systemImage: "star.fill", value: .favorites) {
                    ContactListScreen(title: "Favorites", emptyTitle: "No favorites", emptyMessage: "Tap the star while reviewing a contact.", symbol: "star", items: store.starred, actionTitle: nil, action: nil)
                }
            }
            .tint(.blue)
        } else {
            TabView(selection: $selectedTab) {
                ReviewScreen(openSettings: openSettings)
                    .tabItem { Label("Review", systemImage: "rectangle.stack.fill") }
                    .tag(AppTab.review)
                ContactListScreen(title: "Kept", emptyTitle: "No kept contacts", emptyMessage: "Swipe right on a contact to keep it here.", symbol: "bookmark", items: store.kept, actionTitle: "Remove", action: store.unkeep)
                    .tabItem { Label("Kept", systemImage: "bookmark.fill") }
                    .tag(AppTab.kept)
                ContactListScreen(title: "Deleted", emptyTitle: "No deleted contacts", emptyMessage: "Contacts deleted during this session appear here.", symbol: "trash", items: store.trash, actionTitle: "Restore", action: store.restore)
                    .tabItem { Label("Deleted", systemImage: "trash.fill") }
                    .tag(AppTab.deleted)
                ContactListScreen(title: "Favorites", emptyTitle: "No favorites", emptyMessage: "Tap the star while reviewing a contact.", symbol: "star", items: store.starred, actionTitle: nil, action: nil)
                    .tabItem { Label("Favorites", systemImage: "star.fill") }
                    .tag(AppTab.favorites)
            }
            .tint(.blue)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(colors: [.blue.opacity(0.16), .purple.opacity(0.07), .clear], center: .topLeading, startRadius: 20, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

private struct PermissionScreen: View {
    let symbol: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if #available(iOS 26.0, *) {
                Button(buttonTitle, action: action)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

private struct ReviewScreen: View {
    @Environment(ICloudStore.self) private var store
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.deck.isEmpty {
                    ContentUnavailableView {
                        Label(store.all.isEmpty ? "No contacts to review" : "You’re all caught up", systemImage: store.all.isEmpty ? "person.crop.circle.badge.questionmark" : "checkmark.circle")
                    } description: {
                        Text(emptyMessage)
                    } actions: {
                        if store.hasLimitedAccess {
                            Button("Manage Access", action: openSettings)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        cardDeck
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ContactActions()
                            .frame(height: 62)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Review")
            .modifier(ReviewSubtitle(text: "\(store.deck.count) remaining"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.hasLimitedAccess {
                        Button("Manage Contacts", systemImage: "person.crop.circle.badge.plus", action: openSettings)
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise") { store.load() }
                    }
                }
            }
            .allowsHitTesting(!store.isWorking)
        }
    }

    private var cardDeck: some View {
        let visibleContacts = Array(store.deck.prefix(2))
        return GeometryReader { proxy in
            ZStack {
                ForEach(Array(visibleContacts.enumerated()).reversed(), id: \.element.id) { index, contact in
                    ContactCard(
                        contact: contact,
                        size: proxy.size,
                        interactive: index == 0,
                        onKeep: { store.keep(contact) },
                        onDelete: { store.delete(contact) }
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .shadow(color: .black.opacity(index == 0 ? 0.22 : 0.08), radius: index == 0 ? 24 : 8, y: index == 0 ? 12 : 4)
                    .scaleEffect(index == 0 ? 1 : 0.965)
                    .offset(y: index == 0 ? 0 : 12)
                    .opacity(index == 0 ? 1 : 0.55)
                    .zIndex(index == 0 ? 1 : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(.snappy(duration: 0.28), value: visibleContacts.map(\.id))
    }

    private var emptyMessage: String {
        if !store.all.isEmpty { return "Every contact is in your Kept list." }
        if store.hasLimitedAccess { return "Share more contacts in Settings, then come back here." }
        return "Add a contact in the Contacts app or enable a contacts account in Settings."
    }
}

private struct ContactActions: View {
    @Environment(ICloudStore.self) private var store

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { actionButtons }
        } else {
            actionButtons
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            ActionButton(title: "Delete", systemImage: "trash", color: .red, role: .destructive) {
                if let contact = store.deck.first { store.delete(contact) }
            }
            ActionButton(title: "Undo", systemImage: "arrow.uturn.backward", color: .purple, disabled: store.undo.isEmpty) { store.undoLast() }
            ActionButton(title: store.deck.first?.starred == true ? "Unfavorite" : "Favorite", systemImage: store.deck.first?.starred == true ? "star.fill" : "star", color: .yellow) {
                if let contact = store.deck.first { store.toggleStar(contact) }
            }
            ActionButton(title: "Keep", systemImage: "checkmark", color: .green) {
                if let contact = store.deck.first { store.keep(contact) }
            }
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var role: ButtonRole?
    var disabled = false
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: role, action: action) {
                Image(systemName: systemImage).font(.title3.weight(.semibold)).frame(width: 46, height: 46)
            }
            .buttonStyle(.glass)
            .tint(color)
            .disabled(disabled)
            .accessibilityLabel(title)
        } else {
            Button(role: role, action: action) {
                Image(systemName: systemImage).font(.title3.weight(.semibold)).frame(width: 46, height: 46)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(color)
            .disabled(disabled)
            .accessibilityLabel(title)
        }
    }
}

private struct ContactCard: View {
    let contact: ContactRecord
    let size: CGSize
    let interactive: Bool
    var onKeep: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var drag = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(avatarGradient)
            ContactPhoto(contact: contact)
                .equatable()
                .frame(width: size.width, height: size.height)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.04), .clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                SourceBadges(sources: contact.sources)
                Spacer()
                contactDetails
            }
            .padding(20)
            swipeLabel("KEEP", color: .green, alignment: .topLeading, opacity: keepOpacity, rotation: -12)
            swipeLabel("DELETE", color: .red, alignment: .topTrailing, opacity: deleteOpacity, rotation: 12)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.75) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(drag)
        .rotationEffect(.degrees(interactive ? drag.width / 22 : 0))
        .gesture(interactive ? dragGesture : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction(named: "Keep", onKeep)
        .accessibilityAction(named: "Delete", onDelete)
        .accessibilityHidden(!interactive)
    }

    private var contactDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(contact.displayName).font(.largeTitle.bold()).lineLimit(2)
                if contact.starred {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                }
            }
            if !contact.organization.isEmpty { Label(contact.organization, systemImage: "building.2") }
            if let phone = contact.phones.first { Label(phone, systemImage: "phone") }
            if let email = contact.emails.first { Label(email, systemImage: "envelope").lineLimit(1) }
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .symbolRenderingMode(.hierarchical)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if value.predictedEndTranslation.width > 130 {
                    completeSwipe(direction: 1, action: onKeep)
                } else if value.predictedEndTranslation.width < -130 {
                    completeSwipe(direction: -1, action: onDelete)
                } else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { drag = .zero }
                }
            }
    }

    private func completeSwipe(direction: CGFloat, action: @escaping () -> Void) {
        guard !reduceMotion else { action(); drag = .zero; return }
        withAnimation(.snappy(duration: 0.25)) {
            drag = CGSize(width: direction * 800, height: -30)
        } completion: {
            drag = .zero
            action()
        }
    }

    private func swipeLabel(_ text: String, color: Color, alignment: Alignment, opacity: Double, rotation: Double) -> some View {
        Text(text)
            .font(.title2.weight(.black))
            .tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3) }
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .accessibilityHidden(true)
    }

    private var keepOpacity: Double { Double(min(1, max(0, drag.width / 110))) }
    private var deleteOpacity: Double { Double(min(1, max(0, -drag.width / 110))) }
    private var avatarGradient: LinearGradient {
        var hash: UInt64 = 0
        for byte in contact.displayName.utf8 { hash = hash &* 31 &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360
        return LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.78), Color(hue: hue, saturation: 0.68, brightness: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var accessibilitySummary: String {
        let accounts = contact.sources.isEmpty ? "Unknown account" : contact.sources.map(\.name).joined(separator: ", ")
        return "\(contact.displayName), \(accounts)"
    }
}

private struct SourceBadges: View {
    let sources: [ContactSource]

    var body: some View {
        ScrollView(.horizontal) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) { badges }
            } else {
                badges
            }
        }
        .scrollIndicators(.hidden)
    }

    private var badges: some View {
        HStack(spacing: 8) {
            if sources.isEmpty {
                SourceBadge(name: "Unknown account", systemImage: "questionmark.circle")
            } else {
                ForEach(sources) { source in SourceBadge(name: source.name, systemImage: source.kind.icon) }
            }
        }
    }
}

private struct SourceBadge: View {
    let name: String
    let systemImage: String

    var body: some View {
        let label = Label(name, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
        if #available(iOS 26.0, *) {
            label.glassEffect(.regular, in: .capsule)
        } else {
            label.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct ContactListScreen: View {
    let title: String
    let emptyTitle: String
    let emptyMessage: String
    let symbol: String
    let items: [ContactRecord]
    let actionTitle: String?
    let action: ((ContactRecord) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: symbol, description: Text(emptyMessage))
                } else {
                    List(items) { contact in ContactRow(contact: contact, actionTitle: actionTitle, action: action) }
                        .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(title)
        }
    }
}

private struct ContactRow: View {
    let contact: ContactRecord
    let actionTitle: String?
    let action: ((ContactRecord) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact)
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName).font(.headline)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Label(sourceText, systemImage: sourceIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle) { action(contact) }.buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceText: String { contact.sources.isEmpty ? "Unknown account" : contact.sources.map(\.name).joined(separator: " · ") }
    private var sourceIcon: String { contact.sources.count == 1 ? contact.sources[0].kind.icon : "link" }
}

private struct ReviewSubtitle: ViewModifier {
    let text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(text)
        } else {
            content
        }
    }
}

private struct ContactAvatar: View {
    let contact: ContactRecord

    var body: some View {
        Group {
            if let image = contact.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.accentColor.opacity(0.16)
                    Text(contact.initials).font(.headline).foregroundStyle(.tint)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct ContactPhoto: View, Equatable {
    let contact: ContactRecord

    static func == (lhs: ContactPhoto, rhs: ContactPhoto) -> Bool {
        lhs.contact.id == rhs.contact.id
    }

    var body: some View {
        Group {
            if let image = contact.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
