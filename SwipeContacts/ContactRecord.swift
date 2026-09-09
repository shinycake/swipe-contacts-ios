import Foundation
import UIKit
import Contacts

struct ContactRecord: Identifiable, Hashable {
    let id: String
    var givenName: String
    var familyName: String
    var organization: String
    var phones: [String]
    var emails: [String]
    var thumbnail: Data?
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

    static func from(_ c: CNContact, kept: Bool, starred: Bool) -> ContactRecord {
        ContactRecord(
            id: c.identifier,
            givenName: c.givenName,
            familyName: c.familyName,
            organization: c.organizationName,
            phones: c.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty },
            emails: c.emailAddresses.map { $0.value as String }.filter { !$0.isEmpty },
            thumbnail: c.thumbnailImageData ?? c.imageData,
            kept: kept,
            starred: starred
        )
    }
}

enum UndoKind {
    case keep(ContactRecord)
    case delete(ContactRecord)
}
