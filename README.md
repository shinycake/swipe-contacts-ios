# Swipe Contacts for iOS (iCloud)

Native SwiftUI app. Same swipe rules as the Android Google version, but it only touches the **iCloud Contacts** container via `Contacts.framework`. Keeps, stars, and deletes sync through iCloud to every Apple device.

This Linux box cannot compile or sign an IPA (no Xcode, no iOS SDK). Open the project on a Mac.

## Install on your iPhone

1. Copy `swipe-contacts-ios/` to a Mac with Xcode 15+
2. Open `SwipeContacts.xcodeproj`
3. Signing & Capabilities → Team → your Apple ID
4. Plug in the iPhone, trust the computer
5. Select the device, press Run
6. iPhone Settings → General → VPN & Device Management → trust the developer
7. Grant Contacts. Settings → [your name] → iCloud → Contacts must be on

Free Apple ID signing expires every 7 days. A paid Developer account does not.

## Gestures

- Right / heart = keep → iCloud group **Swipe Kept**
- Left / X = delete → iCloud (Recently Deleted ~30 days)
- Star = iCloud group **Swipe Stars**
- Undo = unkeep, or recreate if already deleted

No toasts. Feedback is the KEEP/DELETE stamp and the card flying off.

Google / Exchange / SIM contacts are ignored.
