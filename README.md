# Swipe Contacts for iOS

Native SwiftUI app using `Contacts.framework`. It loads every contact iOS makes available: all contacts with Full Access, or only selected contacts with Limited Access. An iCloud account is not required.

## Run

1. Open `SwipeContacts.xcodeproj` in Xcode 16 or later.
2. Select the `SwipeContacts` scheme and an iPhone or iOS simulator.
3. For a physical iPhone, choose your development team under Signing & Capabilities.
4. Build and run, then grant Contacts access.

The app refreshes contacts and permission status when it becomes active, including after returning from Settings. A failed fetch shows its error and a retry button; an empty address book shows a separate empty state.

## Gestures

- Right / heart: add to **Swipe Kept** in the contact’s original account.
- Star: add to or remove from **Swipe Stars** in the original account.
- Left / X: delete from the original account.
- Undo: remove the last Keep, or recreate a contact deleted in this session.

Group support and syncing depend on the account provider. Failed writes show an error and leave the visible contact unchanged. Contacts linked across multiple accounts must be deleted using the Contacts app. Trash and undo history last for the current app session; restore recreates the fetched vCard fields with a new identifier and does not restore group memberships. Account-provider recovery features are separate from this app.

## Manual regression checks

Use simulator sample contacts when exercising deletion.

- Grant Full Access with only local contacts: the deck loads without an iCloud gate.
- Keep and star a contact, relaunch, and check persisted membership. Unkeep and undo should return it to the deck.
- Deny access in Settings: the app shows **Contacts locked**. Use **Open Settings**, grant access, and return: the deck reloads.
- Grant Limited Access: only shared contacts appear, with **Manage Contacts Access** available.
- Share no contacts or use an empty address book: show **No contacts to show**, not a loading error.
- Delete a sample contact, restore, and act on the restored card: the new identifier is used.
