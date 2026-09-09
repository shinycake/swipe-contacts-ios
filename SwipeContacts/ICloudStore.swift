import Foundation
import Contacts
import Observation

@Observable
final class ICloudStore {
    enum Phase {
        case boot
        case needAccess
        case denied
        case noICloud
        case ready
    }

    var phase: Phase = .boot
    var accountLabel = "iCloud Contacts"
    var all: [ContactRecord] = []
    var trash: [ContactRecord] = []
    var undo: [UndoKind] = []

    var deck: [ContactRecord] { all.filter { !$0.kept } }
    var kept: [ContactRecord] { all.filter { $0.kept } }
    var starred: [ContactRecord] { all.filter { $0.starred } }

    private let store = CNContactStore()
    private var containerId: String?
    private let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor
    ]

    static let keptGroup = "Swipe Kept"
    static let starGroup = "Swipe Stars"

    func bootstrap() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            load()
        case .denied, .restricted:
            phase = .denied
        case .notDetermined:
            phase = .needAccess
        @unknown default:
            load()
        }
    }

    func requestAccess() async {
        do {
            let ok = try await store.requestAccess(for: .contacts)
            if ok { load() } else { phase = .denied }
        } catch {
            phase = .denied
        }
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                guard let container = try self.findICloudContainer() else {
                    DispatchQueue.main.async { self.phase = .noICloud }
                    return
                }
                self.containerId = container.identifier
                let label = container.name.isEmpty ? "iCloud Contacts" : container.name
                let keptIds = try self.memberIds(in: Self.keptGroup)
                let starIds = try self.memberIds(in: Self.starGroup)
                let pred = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                let raw = try self.store.unifiedContacts(matching: pred, keysToFetch: self.keys)
                let parsed = raw.map {
                    ContactRecord.from($0, kept: keptIds.contains($0.identifier), starred: starIds.contains($0.identifier))
                }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                DispatchQueue.main.async {
                    self.accountLabel = label
                    self.all = parsed
                    self.phase = .ready
                }
            } catch {
                DispatchQueue.main.async { self.phase = .noICloud }
            }
        }
    }

    func keep(_ rec: ContactRecord) {
        guard let idx = all.firstIndex(where: { $0.id == rec.id }) else { return }
        all[idx].kept = true
        undo.append(.keep(all[idx]))
        let id = rec.id
        DispatchQueue.global(qos: .userInitiated).async { self.addToGroup(Self.keptGroup, contactId: id) }
    }

    func unkeep(_ rec: ContactRecord) {
        if let idx = all.firstIndex(where: { $0.id == rec.id }) {
            all[idx].kept = false
        }
        let id = rec.id
        DispatchQueue.global(qos: .userInitiated).async { self.removeFromGroup(Self.keptGroup, contactId: id) }
    }

    func toggleStar(_ rec: ContactRecord) {
        guard let idx = all.firstIndex(where: { $0.id == rec.id }) else { return }
        all[idx].starred.toggle()
        let on = all[idx].starred
        let id = rec.id
        DispatchQueue.global(qos: .userInitiated).async {
            if on { self.addToGroup(Self.starGroup, contactId: id) }
            else { self.removeFromGroup(Self.starGroup, contactId: id) }
        }
    }

    func delete(_ rec: ContactRecord) {
        all.removeAll { $0.id == rec.id }
        trash.insert(rec, at: 0)
        undo.append(.delete(rec))
        let id = rec.id
        DispatchQueue.global(qos: .userInitiated).async { self.deleteICloud(id) }
    }

    func restore(_ rec: ContactRecord) {
        trash.removeAll { $0.id == rec.id }
        var copy = rec
        copy.kept = false
        if !all.contains(where: { $0.id == copy.id }) {
            all.insert(copy, at: 0)
        }
        DispatchQueue.global(qos: .userInitiated).async { self.recreate(copy) }
    }

    func undoLast() {
        guard let last = undo.popLast() else { return }
        switch last {
        case .keep(let rec):
            unkeep(rec)
        case .delete(let rec):
            restore(rec)
        }
    }

    private func findICloudContainer() throws -> CNContainer? {
        let all = try store.containers(matching: nil)
        if let named = all.first(where: { $0.name.localizedCaseInsensitiveContains("icloud") }) {
            return named
        }
        return all.first {
            $0.type == .cardDAV
                && !$0.name.localizedCaseInsensitiveContains("google")
                && !$0.name.localizedCaseInsensitiveContains("gmail")
        }
    }

    private func memberIds(in groupName: String) throws -> Set<String> {
        guard let cid = containerId else { return [] }
        let groups = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: cid))
        guard let group = groups.first(where: { $0.name == groupName }) else { return [] }
        let people = try store.unifiedContacts(
            matching: CNContact.predicateForContactsInGroup(withIdentifier: group.identifier),
            keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
        )
        return Set(people.map(\.identifier))
    }

    private func ensureGroup(_ name: String) throws -> CNGroup {
        guard let cid = containerId else {
            throw NSError(domain: "SwipeContacts", code: 1)
        }
        let groups = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: cid))
        if let existing = groups.first(where: { $0.name == name }) { return existing }
        let g = CNMutableGroup()
        g.name = name
        let req = CNSaveRequest()
        req.add(g, toContainerWithIdentifier: cid)
        try store.execute(req)
        let again = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: cid))
        if let created = again.first(where: { $0.name == name }) { return created }
        throw NSError(domain: "SwipeContacts", code: 2)
    }

    private func addToGroup(_ name: String, contactId: String) {
        do {
            let group = try ensureGroup(name)
            let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
            let req = CNSaveRequest()
            req.addMember(mutable, to: group)
            try store.execute(req)
        } catch {}
    }

    private func removeFromGroup(_ name: String, contactId: String) {
        do {
            guard let cid = containerId else { return }
            let groups = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: cid))
            guard let group = groups.first(where: { $0.name == name }) else { return }
            let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
            let req = CNSaveRequest()
            req.removeMember(mutable, from: group)
            try store.execute(req)
        } catch {}
    }

    private func deleteICloud(_ contactId: String) {
        do {
            let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { return }
            let req = CNSaveRequest()
            req.delete(mutable)
            try store.execute(req)
        } catch {}
    }

    private func recreate(_ rec: ContactRecord) {
        do {
            guard let cid = containerId else { return }
            let m = CNMutableContact()
            m.givenName = rec.givenName
            m.familyName = rec.familyName
            m.organizationName = rec.organization
            m.phoneNumbers = rec.phones.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
            }
            m.emailAddresses = rec.emails.map {
                CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
            }
            if let thumbnail = rec.thumbnail {
                m.imageData = thumbnail
            }
            let req = CNSaveRequest()
            req.add(m, toContainerWithIdentifier: cid)
            try store.execute(req)
        } catch {}
    }
}
