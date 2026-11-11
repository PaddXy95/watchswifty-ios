# TestFlight – Checkliste

Verteilung über einen **öffentlichen TestFlight-Link** (externe Tester). Der erste Build jeder App-Version geht durch
Apples Beta-Prüfung; Builds laufen nach 90 Tagen ab.

## Einmalig
1. **Server-Release** mit der Client-Bibliothek `WatchSwiftyClient` (siehe Server-Repo, CHANGELOG); die App ist auf
   dieses Tag gepinnt (`Packages/WatchSwiftyCore/Package.swift`). `AppInfo.minimumServerVersion` bleibt niedriger:
   Auf älteren Servern blendet die App fehlende Funktionen aus (z. B. Benachrichtigungen vor 0.4.0).
2. **Demo-Instanz** starten (`ops/demo/docker-compose.yml`), unter eigener HTTPS-Adresse erreichbar machen, als `demo`
   anmelden, TMDB-Token unter Konto eintragen, `netflix-sample.csv` aus dem Server-Repo importieren.
3. **App Store Connect:** neue App, Bundle-ID `dev.patmei.watchswifty`, Name „WatchSwifty“, Primärsprache Deutsch.
4. **Datenschutz:** In App Store Connect „Keine Daten erfasst“; Datenschutzerklärung-URL:
   `https://github.com/PaddXy95/watchswifty/blob/main/docs/datenschutz-ios-app.md`.

## Pro Version
1. `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` erhöhen, `xcodegen generate`.
2. Xcode: Team wählen, Product → Archive → Distribute App → TestFlight & App Store.
3. Testinformationen ausfüllen (Texte unten), zur Beta-Prüfung einreichen.
4. Nach der Freigabe: öffentlichen Link aktivieren und in der Server-README eintragen.

## Testinformationen

**Beta-App-Beschreibung (für Tester, deutsch):**
> WatchSwifty ist ein selbst gehosteter Serien- und Film-Tracker. Die App ist das native Gegenstück zur
> Weboberfläche: Weiterschauen, Folgen abhaken, Bewertungen, Verlauf, Bibliothek, Statistik, Importe und Verwaltung.
> Du brauchst einen eigenen WatchSwifty-Server (ab der in der README genannten Version), erreichbar per HTTPS oder
> über dein VPN. Die Anmeldung läuft im Browser-Fenster deines Servers – die App sieht dein Passwort nie.

**Was soll getestet werden:**
> Anmelden, Startseite, Folgen abhaken, Suche, Verlauf bearbeiten.

**Hinweise für die Prüfung (Review Notes, englisch):**
> WatchSwifty is a self-hosted TV/movie tracker; the app connects to the user's own server.
> Demo server: https://<demo-host>
> 1. Enter the demo server address on the first screen and tap "Weiter".
> 2. Tap "Anmelden": the server's login page opens in a browser sheet. User: demo / Password: <demo password>.
> 3. On the "App verbinden" page tap "Verbinden". The app then shows the start screen with sample data.

**Feedback-Adresse:** <eigene Adresse>

**Anmeldedaten:** Benutzer `demo`, Passwort aus `DEMO_ADMIN_PASSWORD`.
