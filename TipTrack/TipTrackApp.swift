import SwiftUI
import SwiftData

@main
struct TipTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // This attaches the permanent database to your app
        .modelContainer(for: Shift.self)
    }
}
