# Entwicklungstagebuch

Kurze Notiz am Ende jedes Arbeitstages: Was entstanden ist, welche Entscheidungen getroffen
wurden und was als Nächstes ansteht.

---

## Tag 2 — 20.09.2026

### Ergebnis

Der Katalog deckt jetzt alle zwölf geplanten Themenbereiche vollständig ab: **51 Skripte in
vier Kategorien**. Neu hinzugekommen ist die Kategorie **Konten**.

### Ausgangspunkt: Lückenanalyse

Der bestehende Katalog wurde gegen die zwölf Themenbereiche geprüft, die das Projekt abdecken
soll. Sechs Bereiche waren vollständig, sechs hatten Lücken:

| Bereich | Stand Tag 1 | Lücke |
|---|---|---|
| Disk und Systemgesundheit | vollständig | — |
| Dienstverwaltung | 3 von 4 | zentraler Bericht über mehrere Computer |
| Windows Update | 4 von 5 | Patch-Compliance über den Bestand |
| Benutzer und Gruppen | 2 von 6 | Anlegen, Sperren, Gruppenbericht |
| Sicherheitsprüfungen | vollständig | — |
| RDP-Verwaltung | 4 von 6 | Sitzungsverlauf, fehlgeschlagene RDP-Logins |
| Netzwerkdiagnose | vollständig | — |
| DNS / DHCP | 5 von 6 | Prüfung einzelner DNS-Einträge |
| Active Directory | 6 von 9 | Computer-Betriebssysteme, Gruppenaudit, deaktivierte Konten |
| Software-Inventar | teilweise | Sammlung über mehrere Computer |
| Hardware-Inventar | vollständig | — |
| Geplante Aufgaben | vollständig | — |

### Neue Kategorie: Konten

Benutzer- und Gruppenverwaltung passte weder unter „System" noch sauber unter „Security" —
Konten anzulegen ist Betrieb, nicht Sicherheitsprüfung. Deshalb eine vierte Kategorie.
Drei bestehende Skripte sind mit umgezogen: `lokale-administratoren`, `ad-inaktive-benutzer`
und `ad-kennwortablauf`. In Security bleiben die reinen Prüf- und Härtungsskripte; die
privilegierten AD-Gruppen bleiben bewusst dort, weil sie eine Sicherheitsfrage sind.

### Die 13 neuen Skripte

**System (3)**

* `dienste-mehrere-computer` — Dienstmatrix über beliebig viele Computer, Quelle wahlweise
  Parameter, Textdatei oder Active Directory. Mit HTML- und CSV-Export.
* `patch-compliance-bericht` — Patchstand je System, Einstufung KONFORM / WARNUNG /
  NICHT KONFORM und eine Gesamtquote. Läuft über Remoting, weil die
  Windows-Update-Schnittstelle nur lokal antwortet.
* `software-inventar-netzwerk` — führt Inventare zusammen, zeigt die Verteilung je Version,
  findet uneinheitliche Versionsstände und beantwortet „wo ist Produkt X noch installiert".

**Netzwerk (1)**

* `dns-eintraege-pruefen` — Einträge einer Zone nach Typ, Prüfung der SRV-Einträge für die
  Domänenanmeldung und Suche nach veralteten A-Einträgen.

**Konten (8)**

* `benutzer-anlegen` — lokale Konten einzeln oder aus CSV
* `konten-aktivieren-deaktivieren` — Offboarding lokal und im AD
* `gruppenmitgliedschaften-lokal` — Gruppen und Mitglieder aus zwei Blickrichtungen
* `lokale-konten-bericht` — alle lokalen Konten plus Aufräumkandidaten
* `ad-benutzer-anlegen` — Onboarding im Stapel aus CSV
* `ad-gruppenmitgliedschaften` — Gruppenaudit aus drei Blickrichtungen
* `ad-computer-betriebssysteme` — OS-Verteilung, Build-Stände, Support-Ende
* `ad-deaktivierte-konten` — deaktiviert, abgelaufen, gesperrt, Löschvorschläge

**Security (1)**

* `rdp-sitzungsverlauf` — führt drei Protokollquellen zusammen: angenommene Verbindungen mit
  Quell-IP (ID 1149), Sitzungsereignisse (IDs 21/23/24/25) und fehlgeschlagene RDP-Anmeldungen
  aus dem Sicherheitsprotokoll.

### Entscheidungen

**Ändernde Skripte laufen standardmäßig als Testlauf.**
Bis Tag 2 las der Katalog nur. Vier der neuen Skripte verändern etwas. Sie tun ohne
`-Anwenden` gar nichts, sondern zeigen eine Vorschau dessen, was passieren würde. Das ist
bewusst umgekehrt zum üblichen `-WhatIf`: der gefährliche Fall braucht die zusätzliche
Eingabe, nicht der harmlose.

**Eingebaute Konten sind gesperrt.**
`konten-aktivieren-deaktivieren` weigert sich, Konten mit SID-Endung `-500` oder `-501`
anzufassen — auch mit `-Anwenden`. Ein versehentlich deaktivierter lokaler Administrator ist
auf einem Server ein sehr teurer Fehler.

**Erzeugte Kennwörter erscheinen nur auf dem Bildschirm.**
Beide Anlege-Skripte zeigen Erstkennwörter einmalig an. Die CSV-Protokolldatei von
`ad-benutzer-anlegen` enthält bewusst keine Kennwortspalte.

**Mehrere Computer: zwei Wege, je nach Datenquelle.**
Wo WMI genügt (Dienste, Datenträger), wird `-ComputerName` genutzt — das braucht kein WinRM.
Wo lokale Schnittstellen nötig sind (Windows Update, Registrierung), läuft die Abfrage über
`Invoke-Command`. Der lokale Rechner wird dabei immer direkt abgefragt, nie über Remoting.

### Geprüft

* Alle 51 Skripte gegen den Parser von Windows PowerShell 5.1 — 0 Fehler
* `catalog.json` gegen das Dateisystem: keine fehlenden Dateien, keine verwaisten Skripte,
  keine doppelten IDs, alle Kategoriezuordnungen gültig
* `dotnet build` — 0 Warnungen, 0 Fehler
* Anwendung gestartet: vier Kategorien in der Leiste, Statusleiste meldet
  „51 Skripte in 4 Kategorien"

### Aufgefallen

* `Sort-Object Computer -Descending, Name` ist ein Syntaxfehler — nach dem Schalter darf keine
  weitere Eigenschaft folgen. Für gemischte Sortierrichtungen braucht es die Hashtable-Form
  `@{ Expression = 'Computer'; Descending = $true }`.
* Die laufende Anwendung sperrt beim Neubauen ihre eigene `AdminWerk.exe`. Vor `dotnet build`
  also beenden.

### Als Nächstes

* [ ] Anwendungssymbol (`.ico`) ergänzen und im Projekt eintragen
* [ ] Skripte als Favoriten markieren können
* [ ] Parameterblock eines Skripts in der Detailansicht gesondert darstellen
* [ ] Suchfeld über `Strg+F` erreichbar machen, Tastaturbedienung insgesamt schärfen
* [ ] Weitere Bereiche erwägen: Drucker, Hyper-V, Zertifikate, Exchange
* [ ] CSV-Vorlagen für die beiden Anlege-Skripte als Beispieldateien mitliefern

---

## Tag 1 — 20.09.2026

### Ergebnis

Die Anwendung steht und läuft: Fenster öffnet sich, Katalog wird geladen, Skripte lassen sich
durchsuchen, anzeigen, kopieren und speichern.

### Was gebaut wurde

**Grundgerüst (WPF, .NET 8, MVVM, keine Fremdbibliotheken)**

* `AdminWerk.sln` und `src/AdminWerk/AdminWerk.csproj` — Ziel `net8.0-windows`
* `App.xaml(.cs)` — setzt Kultur und `FrameworkElement.Language` fest auf `de-DE`,
  damit Datums- und Zahlenformate in der Oberfläche durchgehend deutsch sind
* `Models/` — `ScriptEintrag`, `ScriptKategorie`, `ScriptKatalog`
* `Services/KatalogDienst` — liest `Scripts/catalog.json` und lädt die `.ps1`-Dateien nach
* `ViewModels/HauptViewModel` — Kategoriefilter, Volltextsuche, Befehle
* `Views/PowerShellHervorhebung` — angehängte Eigenschaft, die PowerShell-Quelltext
  eingefärbt in eine `RichTextBox` schreibt
* `Themes/Palette.xaml` und `Themes/Steuerelemente.xaml` — dunkles Farbschema und
  eigene Vorlagen für Schaltflächen, Suchfeld, Listen und Bildlaufleisten

**Oberfläche**

Kopfbereich mit „Admin**Werk**" und dem Untertitel „Windows Administration Suite", darunter
die Kategorieleiste (Alle Skripte / System / Netzwerk / Security). Links die Skriptliste,
rechts die Detailansicht mit Titel, Beschreibung, Kennzeichnungen, Schaltflächen und dem
farblich aufbereiteten Quelltext. Unten eine Statusleiste mit Trefferzahl und Rückmeldungen.

**Skriptkatalog — 38 Skripte**

* System: 13 Skripte (Datenträger, Dienste, Updates, Ereignisprotokoll, Inventar, Prozesse)
* Netzwerk: 10 Skripte (Diagnose, Ports, DNS, DHCP, Firewall, SMB)
* Security: 15 Skripte (Audit mit Bewertung, Defender, BitLocker, Konten, RDP, Active Directory)

### Entscheidungen

**Skripte als eigene `.ps1`-Dateien, nicht eingebettet in JSON.**
Ein Katalog mit eingebetteten Skripttexten wäre unlesbar und im Git-Diff wertlos. So bleibt
jedes Skript für sich lesbar, direkt ausführbar und auch ohne die Anwendung nutzbar.
`catalog.json` enthält nur die Metadaten und verweist auf die Datei.

**Katalog neben der EXE statt als eingebettete Ressource.**
Admins sollen eigene Skripte ergänzen können, ohne das Projekt neu zu bauen. Die Schaltfläche
„Neu laden" liest den Katalog zur Laufzeit erneut ein.

**Die Anwendung führt bewusst keine Skripte aus.**
Ein Werkzeug, das fremden Code mit erhöhten Rechten startet, ist selbst ein Risiko. AdminWerk
stellt Skripte bereit — die Ausführung bleibt eine bewusste Handlung in der PowerShell.

**Kompatibilität mit Windows PowerShell 5.1.**
Auf Servern ist 5.1 weiterhin die Standardumgebung. Konstrukte, die erst ab PowerShell 7
funktionieren (`try` als Ausdruck, `if` als Argument in Klammern), wurden vermieden. Alle
38 Skripte sind gegen `[System.Management.Automation.Language.Parser]::ParseFile` geprüft —
0 Syntaxfehler.

**Gruppen und Konten über SIDs statt über Namen.**
`Get-LocalGroupMember -SID 'S-1-5-32-544'` funktioniert auf deutschen wie englischen Systemen;
`-Group "Administrators"` nicht. Gleiches gilt für das Gastkonto (SID-Endung `-501`) und die
privilegierten AD-Gruppen (RIDs 512/518/519).

### Geprüft

* `dotnet build` — 0 Warnungen, 0 Fehler
* Anwendung gestartet, Fenster gerendert, Screenshot in `docs/bilder/` abgelegt
* Alle 38 Skripte mit dem PowerShell-Parser auf Syntaxfehler geprüft — 0 Fehler
* `catalog.json` gegen das Dateisystem abgeglichen — keine fehlenden, keine verwaisten Skripte

### Aufgefallen

* Ein `Border` kann `Style` nicht gleichzeitig als Attribut und als `<Border.Style>`-Element
  gesetzt bekommen — beim Kennzeichen mit `DataTrigger` musste das Attribut weichen.
* `FlowDocument` bricht Zeilen standardmäßig um. Für Quelltext wird stattdessen eine feste
  `PageWidth` gesetzt, damit waagerecht gescrollt statt umgebrochen wird.

### Als Nächstes

* [ ] Anwendungssymbol (`.ico`) ergänzen und im Projekt eintragen
* [ ] Skripte als Favoriten markieren können
* [ ] Katalog um weitere Bereiche erweitern: Drucker, Hyper-V, Zertifikate, Exchange
* [ ] Suchfeld über `Strg+F` erreichbar machen, Tastaturbedienung insgesamt schärfen
* [ ] Parameterblock eines Skripts in der Detailansicht gesondert darstellen
* [ ] Gedanke: Export mehrerer Skripte als Sammelpaket für ein Zielsystem
