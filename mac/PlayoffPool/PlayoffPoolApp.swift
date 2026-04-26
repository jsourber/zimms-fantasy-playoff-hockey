import SwiftUI

@main
struct PlayoffPoolApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            LeaderboardView()
            #else
            iOSRootView()
            #endif
        }
    }
}
