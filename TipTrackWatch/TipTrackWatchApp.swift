import SwiftUI

@main
struct TipTrackWatchApp: App {
    init() {
        WatchSessionStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
        }
    }
}
