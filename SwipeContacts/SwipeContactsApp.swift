import SwiftUI

@main
struct SwipeContactsApp: App {
    @State private var store = ICloudStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await store.bootstrap() }
        }
    }
}
