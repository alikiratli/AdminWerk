# Entwicklungstagebuch

Kurze Notiz am Ende jedes Arbeitstages: Was entstanden ist, welche Entscheidungen getroffen
wurden und was als Nächstes ansteht.

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
