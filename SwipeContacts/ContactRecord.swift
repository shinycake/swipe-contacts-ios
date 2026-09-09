import Foundation
import UIKit
import Contacts

struct ContactSource: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case local
        case iCloud
        case exchange
        case cardDAV
        case other

        var icon: String {
            switch self {
            case .local: "iphone"
            case .iCloud: "icloud.fill"
            case .exchange: "building.2.fill"
            case .cardDAV: "server.rack"
            case .other: "person.crop.circle.badge.questionmark"
            }
        }
    }

    let id: String
    let name: String
    let kind: Kind

    static func from(_ container: CNContainer) -> ContactSource {
        let trimmedName = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        let kind: Kind

        switch container.type {
        case .local:
            name = "On My iPhone"
            kind = .local
        case .exchange:
            name = trimmedName.isEmpty ? "Exchange" : trimmedName
            kind = .exchange
        case .cardDAV:
            if trimmedName.localizedCaseInsensitiveContains("icloud") {
                name = "iCloud"
                kind = .iCloud
            } else {
                name = trimmedName.isEmpty ? "CardDAV" : trimmedName
                kind = .cardDAV
            }
        case .unassigned:
            name = trimmedName.isEmpty ? "Other" : trimmedName
            kind = .other
        @unknown default:
            name = trimmedName.isEmpty ? "Other" : trimmedName
            kind = .other
        }

        return ContactSource(id: container.identifier, name: name, kind: kind)
    }
}

struct ContactRecord: Identifiable, Hashable, Sendable {
    let id: String
    var givenName: String
    var familyName: String
    var organization: String
    var phones: [String]
    var emails: [String]
    var thumbnail: Data?
    var sources: [ContactSource]
    var kept: Bool
    var starred: Bool

    var displayName: String {
        let n = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !n.isEmpty { return n }
        if !organization.isEmpty { return organization }
        if let p = phones.first { return p }
        if let e = emails.first { return e }
        return "No name"
    }

    var subtitle: String {
        if let p = phones.first { return p }
        if let e = emails.first { return e }
        return organization
    }

    var initials: String {
        let a = givenName.first.map(String.init) ?? familyName.first.map(String.init) ?? "?"
        let b = familyName.first.map(String.init) ?? ""
        return (a + b).uppercased()
    }

    var image: UIImage? {
        guard let thumbnail, let img = UIImage(data: thumbnail) else { return nil }
        return img
    }

    static func from(
        _ c: CNContact,
        sources: [ContactSource] = [],
        kept: Bool,
        starred: Bool
    ) -> ContactRecord {
        ContactRecord(
            id: c.identifier,
            givenName: c.givenName,
            familyName: c.familyName,
            organization: c.organizationName,
            phones: c.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty },
            emails: c.emailAddresses.map { $0.value as String }.filter { !$0.isEmpty },
            thumbnail: c.thumbnailImageData ?? c.imageData,
            sources: sources,
            kept: kept,
            starred: starred
        )
    }
}

enum UndoKind {
    case keep(ContactRecord)
    case delete(ContactRecord)
}
