# ByCS Lernclient für iOS

Ein kleiner iOS-Client in SwiftUI für die [ByCS-Lernplattform](https://lernplattform.bycs.de/my/courses.php). Die Kursübersicht ist die Startseite und über **Meine Kurse** jederzeit erreichbar. Native Bedienelemente bieten Navigation, Laden, Teilen und Dateiexport. Kurse, Aufgaben, Foren, Tests und die ByCS-Anmeldung erscheinen in einem `WKWebView`, damit die tatsächlich von der Schule freigeschalteten Moodle-Funktionen nutzbar bleiben.

## Starten

1. `ByCSLernclient.xcodeproj` mit Xcode 15 oder neuer öffnen.
2. Ein iPhone oder einen iOS-Simulator mit iOS 16.4 oder neuer wählen und **Run** drücken.
3. Für ein echtes Gerät unter **Signing & Capabilities** das eigene Team und eine eindeutige Bundle ID wählen.
4. Unter **Weitere Optionen → Anmeldedaten speichern** die ByCS-Kennung und das Passwort einmalig eingeben. Die App speichert beides nur auf diesem Gerät im iOS-Schlüsselbund und meldet sich bei einer erneuten ByCS-Anmeldemaske automatisch an.
5. Änderungen des Passworts, MFA und Nutzungsbedingungen werden auf der offiziellen Anmeldeseite abgewickelt. Nach einer Passwortänderung müssen die gespeicherten Daten in der App aktualisiert werden.

## GitHub Actions

Jeder Push auf `main` sowie ein manueller Start über **Actions → Build iOS IPA → Run workflow** erzeugen das Artefakt `ByCSLernclient-unsigned-ipa`. Unter dem jeweiligen Run kann die IPA als ZIP-Artefakt heruntergeladen werden. Der Build nutzt einen macOS-Runner und erstellt ein Archiv für echte iOS-Geräte.

**Die IPA ist unsigniert und lässt sich so nicht auf einem iPhone installieren.** Für eine installierbare IPA braucht es ein Apple-Developer-Team, eine passende Bundle ID, ein Zertifikat und ein Provisioning-Profil. Diese privaten Daten gehören nicht in das Repository. In Xcode kann die App mit dem eigenen Team direkt auf ein Gerät gebaut werden.

Die App verwendet den dauerhaften Website-Datenspeicher von WebKit. Nach einem Neustart werden gültige Sitzungscookies wiederverwendet. Sind sie abgelaufen, trägt die App auf `https://auth.bycs.de` die freiwillig gespeicherten Zugangsdaten in das ByCS-Loginformular ein. Ein fehlgeschlagener automatischer Versuch wird nicht wiederholt, bis die Daten neu gespeichert oder die Anmeldung manuell abgeschlossen wurde. MFA kann weiterhin eine manuelle Bestätigung erfordern. Über **Weitere Optionen → Abmelden** werden gespeicherte Zugangsdaten, Cookies und Website-Daten entfernt. Im Menü **Anmeldedaten ändern** können die Daten getrennt von einer aktiven Sitzung gelöscht werden.

Nach der Anmeldung wird `/my/courses.php` geladen. Falls ByCS stattdessen zunächst den allgemeinen Schreibtisch unter `/my/` öffnet, führt die App einmalig weiter zur Kursübersicht.

## Grenzen

- Dies ist eine native Swift-App mit integrierter Webansicht, kein vollständiger nativer Moodle-Datenclient. Für eine eigenständige native Darstellung von Kursen, Aufgaben und Mitteilungen wäre eine vom Betreiber freigegebene API samt Authentifizierungsverfahren erforderlich.
- Alle Inhalte benötigen eine Internetverbindung. Es gibt keinen Offline-Abgleich und keine Push-Mitteilungen.
- Manche externen Kurswerkzeuge öffnen eine neue Seite; diese wird im selben Webbereich geladen. Die jeweilige Domain steht stets oben in der App.
- Unverschlüsselte HTTP-Links werden abgewiesen. Anhänge können über die iOS-Teilenansicht in Dateien gespeichert werden.
- Funktion und Login müssen mit einem freigeschalteten ByCS-Konto auf einem iPhone geprüft werden. In dieser Linux-Umgebung steht Xcode nicht zur Verfügung.

## Quellen

- [ByCS: Anmeldung an der Lernplattform](https://www.bycs.de/hilfe-und-tutorials/lernplattform/in-der-lernplattform-anmelden/index.html)
- [ByCS: Schreibtisch direkt aufrufen](https://www.bycs.de/hilfe-und-tutorials/lernplattform/schreibtisch-aufrufen/index.html)
- [ByCS: Lernplattform und Moodle-Basis](https://www.bycs.de/uebersicht-und-funktionen/lernplattform/index.html)

Unabhängiges Projekt; keine offizielle ByCS-App.
