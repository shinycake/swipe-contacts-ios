import Foundation
import Contacts
import Observation

@Observable
@MainActor
final class ICloudStore {
    enum Phase: Equatable {
        case boot, needAccess, denied, failed, ready
    }

    var phase: Phase = .boot
    var accountLabel = "All Contacts"
    var all: [ContactRecord] = []
    var trash: [ContactRecord] = []
    var undo: [UndoKind] = []
    var errorMessage: String?
    var loadError = ""
    var isWorking = false
    var hasLimitedAccess = false

    var deck: [ContactRecord] { all.filter { !$0.kept } }
    var kept: [ContactRecord] { all.filter { $0.kept } }
    var starred: [ContactRecord] { all.filter { $0.starred } }

    private let repository = ContactsRepository()

    func bootstrap() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited {
            hasLimitedAccess = true
            load()
            return
        }
        hasLimitedAccess = false
        switch status {
        case .authorized:
            load()
        case .denied, .restricted:
            all = []
            trash = []
            undo = []
            phase = .denied
        case .notDetermined:
            phase = .needAccess
        default:
            loadError = "This contacts access setting is not supported. Check Contacts access in Settings."
            phase = .failed
        }
    }

    func requestAccess() async {
        do {
            _ = try await repository.requestAccess()
            await bootstrap()
        } catch {
            loadError = error.localizedDescription
            phase = .failed
        }
    }

    func load() {
        guard !isWorking else { return }
        isWorking = true
        if phase != .ready { phase = .boot }
        Task {
            defer { isWorking = false }
            do {
                let result = try await repository.load()
                // Permission may change while a fetch is running.
                let status = CNContactStore.authorizationStatus(for: .contacts)
                guard status != .denied && status != .restricted else {
                    all = []
                    phase = .denied
                    return
                }
                accountLabel = hasLimitedAccess ? "Selected Contacts" : "All Contacts"
                all = result.contacts
                errorMessage = result.warning
                phase = .ready
            } catch {
                let status = CNContactStore.authorizationStatus(for: .contacts)
                all = []
                loadError = error.localizedDescription
                phase = status == .denied || status == .restricted ? .denied : .failed
            }
        }
    }

    func keep(_ rec: ContactRecord) {
        guard !isWorking, let index = all.firstIndex(where: { $0.id == rec.id }) else { return }
        let previous = all[index]
        all[index].kept = true
        undo.append(.keep(previous))
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                try await repository.setMembership(true, groupName: ContactsRepository.keptGroup, contactId: rec.id)
            } catch {
                if let current = all.firstIndex(where: { $0.id == rec.id }) {
                    all[current].kept = previous.kept
                }
                if case .keep(let last)? = undo.last, last.id == rec.id {
                    undo.removeLast()
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func unkeep(_ rec: ContactRecord) {
        guard !isWorking, let index = all.firstIndex(where: { $0.id == rec.id }) else { return }
        let wasKept = all[index].kept
        all[index].kept = false
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                try await repository.setMembership(false, groupName: ContactsRepository.keptGroup, contactId: rec.id)
            } catch {
                if let current = all.firstIndex(where: { $0.id == rec.id }) {
                    all[current].kept = wasKept
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleStar(_ rec: ContactRecord) {
        guard !isWorking, let index = all.firstIndex(where: { $0.id == rec.id }) else { return }
        let previous = all[index].starred
        let target = !previous
        all[index].starred = target
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                try await repository.setMembership(target, groupName: ContactsRepository.starGroup, contactId: rec.id)
            } catch {
                if let current = all.firstIndex(where: { $0.id == rec.id }) {
                    all[current].starred = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ rec: ContactRecord) {
        guard !isWorking, let index = all.firstIndex(where: { $0.id == rec.id }) else { return }
        all.remove(at: index)
        trash.insert(rec, at: 0)
        undo.append(.delete(rec))
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                try await repository.delete(rec.id)
            } catch {
                trash.removeAll { $0.id == rec.id }
                all.insert(rec, at: min(index, all.endIndex))
                if case .delete(let last)? = undo.last, last.id == rec.id {
                    undo.removeLast()
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func restore(_ rec: ContactRecord) {
        change {
            try await self.performRestore(rec)
            self.undo.removeAll {
                if case .delete(let deleted) = $0 { return deleted.id == rec.id }
                return false
            }
        }
    }

    private func performRestore(_ rec: ContactRecord) async throws {
        let restored = try await repository.restore(rec.id)
        trash.removeAll { $0.id == rec.id }
        all.insert(restored, at: 0)
    }

    func undoLast() {
        guard !isWorking, let last = undo.last else { return }
        switch last {
        case .keep(let rec):
            _ = undo.popLast()
            guard let index = all.firstIndex(where: { $0.id == rec.id }) else { return }
            all[index].kept = false
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await repository.setMembership(false, groupName: ContactsRepository.keptGroup, contactId: rec.id)
                } catch {
                    if let current = all.firstIndex(where: { $0.id == rec.id }) {
                        all[current].kept = true
                    }
                    undo.append(last)
                    errorMessage = error.localizedDescription
                }
            }
        case .delete:
            change {
                if case .delete(let rec) = last { try await self.performRestore(rec) }
                _ = self.undo.popLast()
            }
        }
    }

    private func change(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

// Contacts.framework performs synchronous I/O. This actor keeps it off the UI
// actor and serializes reads, group creation, and saves.
private actor ContactsRepository {
    static let keptGroup = "Swipe Kept"
    static let starGroup = "Swipe Stars"

    struct Snapshot: Sendable {
        var contacts: [ContactRecord]
        var warning: String?
    }

    private let store = CNContactStore()
    private var deleted: [String: (contact: CNContact, containerId: String)] = [:]
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

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    func load() throws -> Snapshot {
        // Enumerate exactly the contacts iOS authorizes. Container names and
        // CardDAV types do not reliably identify an iCloud account.
        var records: [ContactRecord] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        try store.enumerateContacts(with: request) { contact, _ in
            let sources = (try? self.containers(for: contact.identifier))?
                .map(ContactSource.from)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                ?? []
            records.append(ContactRecord.from(contact, sources: sources, kept: false, starred: false))
        }
        var warning: String?
        do {
            let groups = try store.groups(matching: nil)
            let keptIds = try memberIds(in: groups.filter { $0.name == Self.keptGroup })
            let starIds = try memberIds(in: groups.filter { $0.name == Self.starGroup })
            for index in records.indices {
                records[index].kept = keptIds.contains(records[index].id)
                records[index].starred = starIds.contains(records[index].id)
            }
        } catch {
            // Group support is account-specific; it must not hide the address book.
            warning = "Contacts loaded, but saved Keep and Star lists could not be read. " + error.localizedDescription
        }
        records.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return Snapshot(contacts: records, warning: warning)
    }

    private func memberIds(in groups: [CNGroup]) throws -> Set<String> {
        var ids = Set<String>()
        for group in groups {
            let people = try store.unifiedContacts(
                matching: CNContact.predicateForContactsInGroup(withIdentifier: group.identifier),
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
            )
            ids.formUnion(people.map(\.identifier))
        }
        return ids
    }

    private func containers(for contactId: String) throws -> [CNContainer] {
        let containers = try store.containers(matching: CNContainer.predicateForContainerOfContact(withIdentifier: contactId))
        guard !containers.isEmpty else {
            throw NSError(domain: "SwipeContacts", code: 1, userInfo: [NSLocalizedDescriptionKey: "The contact’s account is no longer available. Reopen the app and try again."])
        }
        return containers
    }

    func setMembership(_ included: Bool, groupName: String, contactId: String) throws {
        let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
        let request = CNSaveRequest()
        for container in try containers(for: contactId) {
            let groups = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: container.identifier))
            if let group = groups.first(where: { $0.name == groupName }) {
                let isMember = try memberIds(in: [group]).contains(contactId)
                if included && !isMember { request.addMember(contact, to: group) }
                if !included && isMember { request.removeMember(contact, from: group) }
            } else if included {
                let group = CNMutableGroup()
                group.name = groupName
                // Persist the group before a membership request references it.
                // Some stores reject a group created in that same save request.
                let creation = CNSaveRequest()
                creation.add(group, toContainerWithIdentifier: container.identifier)
                try store.execute(creation)
                let savedGroups = try store.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: container.identifier))
                guard let savedGroup = savedGroups.first(where: { $0.name == groupName }) else {
                    throw NSError(domain: "SwipeContacts", code: 4, userInfo: [NSLocalizedDescriptionKey: "The contact’s account could not create the list. Please try again."])
                }
                request.addMember(contact, to: savedGroup)
            }
        }
        try store.execute(request)
    }

    func delete(_ contactId: String) throws {
        let source = try containers(for: contactId)
        guard source.count == 1 else {
            throw NSError(domain: "SwipeContacts", code: 2, userInfo: [NSLocalizedDescriptionKey: "This contact links multiple accounts. Delete it in the Contacts app so you can choose which account to change."])
        }
        let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys + [CNContactVCardSerialization.descriptorForRequiredKeys()])
        let request = CNSaveRequest()
        request.delete(contact.mutableCopy() as! CNMutableContact)
        try store.execute(request)
        deleted[contactId] = (contact, source[0].identifier)
    }

    func restore(_ contactId: String) throws -> ContactRecord {
        guard let original = deleted[contactId] else {
            throw NSError(domain: "SwipeContacts", code: 3, userInfo: [NSLocalizedDescriptionKey: "This contact can no longer be restored from this session."])
        }
        // A vCard round-trip creates a new identifier and retains the fetched
        // contact fields. Never reuse the identifier of the deleted record.
        let data = try CNContactVCardSerialization.data(with: [original.contact])
        let copy = try CNContactVCardSerialization.contacts(with: data)[0].mutableCopy() as! CNMutableContact
        let request = CNSaveRequest()
        request.add(copy, toContainerWithIdentifier: original.containerId)
        try store.execute(request)
        deleted.removeValue(forKey: contactId)
        let saved = try store.unifiedContact(withIdentifier: copy.identifier, keysToFetch: keys)
        let source = try store.containers(
            matching: CNContainer.predicateForContainerOfContact(withIdentifier: saved.identifier)
        ).map(ContactSource.from)
        return ContactRecord.from(saved, sources: source, kept: false, starred: false)
    }
}
