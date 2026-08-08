import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            StoreView()
                .tabItem { Label("Store", systemImage: "bag.fill") }

            InstalledView()
                .tabItem { Label("Installed", systemImage: "square.stack.3d.up.fill") }

            SourcesView()
                .tabItem { Label("Sources", systemImage: "tray.full.fill") }

            SignIPAView()
                .tabItem { Label("Sign IPA", systemImage: "signature") }

            DeviceView()
                .tabItem { Label("Device", systemImage: "iphone.and.arrow.forward") }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}
