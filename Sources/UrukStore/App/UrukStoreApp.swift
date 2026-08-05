import SwiftUI

@main
struct UrukStoreApp: App {
    @StateObject private var sourceManager = SourceManager()
    @StateObject private var installManager = InstallManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(sourceManager)
                .environmentObject(installManager)
        }
    }
}
