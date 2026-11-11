# WatchSwifty für iOS

Native iPhone-App für [WatchSwifty](https://github.com/PaddXy95/watchswifty), den selbst gehosteten Serien- und
Film-Tracker. Die App kann dasselbe wie die Weboberfläche und spricht nur mit deinem eigenen Server (App-API
`/api/v1`). Angemeldet wird im Browser-Fenster – die App sieht dein Passwort nie.

## Voraussetzungen
- Xcode 26 oder neuer, iOS 26 oder neuer (nur iPhone)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Während der Entwicklung liegt das Server-Repo `watchswifty` direkt neben diesem Repo
  (`../watchswifty`); daraus kommt die Client-Bibliothek `WatchSwiftyClient`.

## Bauen
```bash
xcodegen generate
open WatchSwifty.xcodeproj
```
Beim ersten Öffnen fragt Xcode, ob das Plugin `OpenAPIGenerator` ausgeführt werden darf („Trust & Enable“).

## Tests
```bash
swift test --package-path Packages/WatchSwiftyCore
```

## Aufbau
- `WatchSwifty/` – App-Target: SwiftUI-Bildschirme, Ressourcen.
- `Packages/WatchSwiftyCore/` – Logik ohne Oberfläche (Stores, Anmeldung, Netzwerk), mit `swift test` auf dem Mac
  testbar.
- Konzept: `docs/superpowers/specs/2026-11-10-ios-app-design.md` im Server-Repo.
