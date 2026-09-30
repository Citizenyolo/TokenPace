import SwiftUI
import WidgetKit

@main
struct TokenPaceApp: App {
    // Keep a reference to the observer so it stays alive
    @StateObject private var observer = QuotaObserver()

    var body: some Scene {
        // App is LSUIElement so it has no UI, but we must return a Scene
        Settings {
            EmptyView()
        }
    }
}
