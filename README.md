# UrukStore

An alternative iOS app store / sideloading client — same idea as AltStore
and SideStore, built independently, targeting a Mac-free workflow end to
end (built via GitHub Actions, no local Xcode required).

Repo source format is compatible with existing AltStore/SideStore JSON
feeds, so community repos work without conversion.

## Status

### What's implemented
- SwiftUI app: Store / Installed / Sources / Sign IPA / Device / Account tabs
- `Source` / `StoreApp` models matching the AltStore repo JSON schema
- Real Apple ID signing via AltSign (github.com/SideStore/AltSign) — GSA
  auth with 2FA, certificate/App ID/provisioning profile handling,
  Keychain-cached certificates so repeat signs don't hit Apple's
  per-account certificate limit
- Local `.ipa` signing (Sign IPA tab) — pick any unsigned IPA, sign it,
  share it out
- **Real device install over a local VPN tunnel** — using minimuxer
  (github.com/SideStore/minimuxer), the same library SideStore uses.
  Import a `.mobiledevicepairing` pairing file in the Device tab, have a
  local VPN tunnel app (e.g. StosVPN) running, and installs from the
  Store tab or Sign IPA push straight to the device — no cable
- GitHub Actions workflow: XcodeGen generates the `.xcodeproj` in CI,
  builds an unsigned IPA, and publishes it as a GitHub Release

### Requirements for on-device install
1. A `.mobiledevicepairing` pairing file for your device (see
   docs.sidestore.io/docs/advanced/pairing-file)
2. A local VPN tunnel app installed and running (e.g. StosVPN) — this is
   what makes the device reachable without USB
3. Signed in with your Apple ID (Account tab)

Without a pairing file, signing still works — UrukStore falls back to
just handing you the signed `.ipa` to share elsewhere (LiveContainer,
AirDrop, Files).

### Known limitations
- Sessions (Apple ID sign-in) aren't persisted across app launches yet —
  in-memory only, so you'll need to sign in again each time
- Certificate private keys ARE cached in Keychain across launches, so
  repeated installs don't hit Apple's certificate limit

## Building

Locally (needs a Mac with Xcode 17+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)):
```
xcodegen generate
open UrukStore.xcodeproj
```

Via CI: push to `main`, or run the **Build Unsigned IPA** workflow
manually — the `.ipa` is published as a GitHub Release.

## Project structure
```
Sources/UrukStore/
  App/        — app entry point, Info.plist
  Models/     — Source, StoreApp, InstalledApp
  Services/   — SourceManager, InstallManager, SigningService,
                AnisetteClient, CertificateKeychain, IPAInspector,
                DeviceConnection, NetworkClient
  Views/      — RootTabView, StoreView, AppDetailView, InstalledView,
                SourcesView, SignIPAView, DeviceView, AccountView
project.yml   — XcodeGen spec (generates the .xcodeproj in CI)
.github/workflows/build.yml
```
