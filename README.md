# UrukStore

An alternative iOS app store / sideloading client — same idea as AltStore
and SideStore, built independently, targeting a Mac-free workflow end to
end (built via GitHub Actions, no local Xcode required).

Repo source format is compatible with existing AltStore/SideStore JSON
feeds, so community repos work without conversion.

## Status: early scaffold (phase 1)

This first push is the app shell and CI pipeline. It **builds and runs**,
can add sources and browse apps, but **install/sign/JIT are stubbed** —
calling them returns a clear "not implemented" error instead of pretending
to work. That's intentional: those three pieces are genuinely hard and
each deserves its own milestone rather than a half-working fake.

### What's implemented
- SwiftUI app: Store / Installed / Sources tabs
- `Source` / `StoreApp` models matching the AltStore repo JSON schema
- Adding, removing, refreshing repo sources
- Browsing apps across multiple sources
- GitHub Actions workflow producing an unsigned `.ipa` on every push
  (XcodeGen generates the `.xcodeproj` in CI so nothing binary is
  committed to the repo)

### What's not implemented yet (roadmap)
| Piece | What it needs | Notes |
|---|---|---|
| Signing | A broker that talks to Apple's `developerservices2` API to request a free-account provisioning profile, same negotiation Xcode/AltServer do | `SigningService.swift` has the protocol shaped for this; needs a companion server component since it's a stateful multi-step handshake, not something to do purely on-device |
| Wireless install | lockdown/AFC protocol over local network (same one Xcode's wireless debugging uses) | `InstallManager.install(_:from:)` is where this plugs in |
| Auto re-sign before expiry | Push notification (APNs) or background refresh that re-runs the signing flow every ~6 days | Depends on Signing being done first |
| JIT enablement | Tunnel to the on-device `debugserver` (StosVPN-style) + JIT trigger commands | Separate module, independent of the above three |

### Why phase this instead of building it all at once
Signing and JIT are the parts that make or break reliability — building
them properly (with error handling for Apple's rate limits, expired
sessions, etc.) needs real device testing, which is best done as its own
focused pass rather than bolted onto initial scaffolding.

## Building

Locally (needs a Mac with Xcode 16 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)):
```
xcodegen generate
open UrukStore.xcodeproj
```

Via CI: push to `main`, or run the **Build Unsigned IPA** workflow
manually — the `.ipa` shows up as a workflow artifact.

## Project structure
```
Sources/UrukStore/
  App/        — app entry point, Info.plist
  Models/     — Source, StoreApp, InstalledApp
  Services/   — SourceManager, InstallManager, SigningService, NetworkClient
  Views/      — RootTabView, StoreView, AppDetailView, InstalledView, SourcesView
project.yml   — XcodeGen spec (generates the .xcodeproj in CI)
.github/workflows/build.yml
```
