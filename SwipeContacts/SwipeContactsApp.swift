import SwiftUI

@main
struct SwipeContactsApp: App {
    @State private var store = ICloudStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.bootstrap() } }
                }
        }
    }
}
