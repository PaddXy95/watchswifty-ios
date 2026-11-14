# CLAUDE.md

WatchSwifty iOS app: SwiftUI, iOS 26+, iPhone only, Swift 6 strict concurrency. Talks only to the WatchSwifty App
API through the generated `WatchSwiftyClient` (server repo `PaddXy95/watchswifty`, pinned to a release tag in
`Packages/WatchSwiftyCore/Package.swift`; for unreleased server changes use `path: "../../../watchswifty"` locally,
never committed). No local database: stores hold the generated API types. Design: `../watchswifty/docs/superpowers/specs/2026-11-10-ios-app-design.md`,
plan: `../watchswifty/docs/superpowers/plans/2026-11-11-ios-app.md`.

**Languages:** everything the user sees is German (String Catalog `de` only); code identifiers and comments English;
commits English Conventional Commits.

## Commands
```bash
swift test --package-path Packages/WatchSwiftyCore        # logic tests (Swift Testing, macOS host)
xcodebuild -project WatchSwifty.xcodeproj -scheme WatchSwifty -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation -derivedDataPath build/DerivedData build
```

## Rules
- The Xcode project is checked in as `WatchSwifty.xcodeproj/project.xcproj` (Xcode 27.2 JSON format). `WatchSwifty/`
  is a synchronized folder: new files need no project change. Change build settings in Xcode or with
  `xcrun xcodeproj setting set [--target WatchSwifty] <KEY> <VALUE>`, then `xcrun xcprojformatter --update WatchSwifty.xcodeproj`.
- `WatchSwiftyCore` has no SwiftUI views and no UIKit; views live in the app target.
- Stores: `@MainActor @Observable`, depend on `any APIProtocol`; tests use `FakeTransport` with the real `Client`.
- The device token lives only in the Keychain and never appears in logs or UI.
- The app never recomputes server logic (next episode, stats, matching): it shows what the API returns.
