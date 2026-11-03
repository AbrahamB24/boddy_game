# Crashlytics einrichten (Absturzberichte)

Der Code ist eingebaut, aber **ausgeschaltet, bis du ein Firebase-Projekt verbindest**.
Ohne die Datei aus Schritt 2 baut und läuft das Spiel genau wie vorher.

**Gilt nur für die Handy-App (APK / iOS).** Für die Web-Version gibt es Crashlytics
nicht. Die Web-Version testest du weiter wie bisher, dort bringt Crashlytics nichts.

## Was du tun musst (einmalig, ca. 10 Minuten)

1. **Firebase-Projekt anlegen:** https://console.firebase.google.com → „Projekt hinzufügen“
   (Google Analytics kannst du aus lassen).
2. **Android-App registrieren:** Projekt-Übersicht → Android-Symbol. Paketname:
   `com.boddy.boddygame`. Die Datei **`google-services.json`** herunterladen und nach
   **`android/app/google-services.json`** kopieren.
3. **Crashlytics aktivieren:** Firebase-Konsole → Build → Crashlytics → „Aktivieren“.
4. **Neu bauen:** `flutter build apk --release` (oder `flutter run --release` auf dem Handy).
   Ein Debug-Build sendet nichts, ausser du startest ihn mit
   `flutter run --dart-define=CRASH_REPORTING=true`.
5. **Prüfen:** App starten, einen Absturz auslösen (oder abwarten), dann in der Konsole unter
   Crashlytics nachsehen. Der erste Bericht erscheint oft erst nach dem **nächsten** Start der App.

## Was gemeldet wird

- Jeder nicht abgefangene Flutter-Fehler (Layout-Fehler, Exceptions im UI) als *nicht fatal*.
- Jeder nicht abgefangene Fehler in asynchronem Code als *fatal*.
- Native Abstürze (Speicher, Absturz des Prozesses) meldet Crashlytics selbst, also auch ein
  Absturz beim Laden der Karte, falls er dort durch zu wenig Speicher entsteht (nur eine Vermutung).
- Jeder Bericht trägt die **Konto-ID** (keine Namen, keine Adresse).

## Wenn die Datei fehlt

Der Build schaltet die Firebase-Plugins nur ein, wenn `android/app/google-services.json`
existiert. Fehlt sie, oder ist das Handy ohne Google-Dienste, steht im Log
`[CrashReporting] off: …` und das Spiel startet normal.

## iOS (später)

Dafür braucht es zusätzlich `GoogleService-Info.plist` (aus derselben Firebase-Konsole) in
`ios/Runner/` und einen Mac zum Bauen. Der Dart-Code ist bereits für iOS vorbereitet.

## Wo im Code

- `lib/core/diagnostics/crash_reporting.dart`: Ein- und Ausschalter, Handler, `note(...)` für
  abgefangene Probleme, `setUser(...)`.
- `lib/main.dart`: ruft `CrashReporting.init()` beim Start auf, setzt die Konto-ID.
- `android/settings.gradle.kts`, `android/app/build.gradle.kts`: Firebase-Plugins, bedingt aktiv.
