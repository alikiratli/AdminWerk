# Entwicklungstagebuch

Kurze Notiz am Ende jedes Arbeitstages: Was entstanden ist, welche Entscheidungen getroffen
wurden und was als Nächstes ansteht.

---

## Tag 3 — 21.09.2026

### Ergebnis

Drei Dinge, in dieser Reihenfolge: eine **CI**, die einlöst was das README zusichert, ein
**Parameter-Assistent**, der aus dem `param()`-Block ein Formular baut, und **In PowerShell
öffnen** als Weg von der Anwendung in die Sitzung — ohne dass AdminWerk etwas ausführt.

Angefangen hat der Tag mit etwas anderem: beim Starten der Anwendung meldete die
UI-Automation für jeden Listeneintrag `AdminWerk.Models.ScriptKategorie` statt der
Beschriftung. Eine Sprachausgabe hätte nichts Brauchbares vorgelesen.

### Barrierefreiheit

Die `ListBoxItem`s hatten weder Textinhalt noch `AutomationProperties.Name` — WPF fällt dann
auf `ToString()` des Modells zurück. Beide `ItemContainerStyle` setzen jetzt Name und
HelpText aus dem Modell; die Sternschaltfläche führt den Skripttitel mit, weil dreizehn
gleichnamige Schaltflächen in einer Liste nicht unterscheidbar wären. Das Suchfeld war
ebenfalls namenlos: sein Platzhalter ist ein eigener `TextBlock` und gehört der Automation
nicht zum Eingabefeld.

Gegenprobe: `FindFirst(NameProperty, "Security")` findet den Reiter jetzt und wählt ihn aus.
Vorher scheiterte genau das.

### CI

`.github/workflows/pruefung.yml` prüft bei jedem Push und Pull Request den Release-Build
(Warnungen als Fehler) und den Skriptkatalog. `tools/katalog-pruefen.ps1` erledigt Syntax,
Katalogabgleich und Pflichtangaben in einem Durchlauf und läuft bewusst unter Windows
PowerShell 5.1.

### Entscheidungen

**Der Parser allein ist kein 5.1-Test.**
Bisher galt `Parser::ParseFile` mit 0 Fehlern als Beleg für 5.1-Tauglichkeit. Nachgemessen
stimmt das nicht. Von den beiden Konstrukten, die bisher als verboten notiert waren, erzeugt
keines einen Parserfehler:

| Konstrukt | Parser 5.1 | Laufzeit 5.1 |
|---|---|---|
| `$x = try { 1 } catch { 2 }` | 0 Fehler | läuft, `$x` ist 42 |
| `-ForegroundColor (if … )` | 0 Fehler | *„if wurde nicht als Name eines Cmdlet erkannt"*, Exitcode trotzdem 0 |
| `$a ?? 'x'`, `$a ? 1 : 2` | 1 Fehler | — |

Das erste war schlicht eine Fehlannahme: `try` als Ausdruck funktioniert unter 5.1.19041.
Das zweite scheitert erst zur Laufzeit, und der Exitcode bleibt dabei 0 — ein reiner
Testlauf hätte es also auch nicht gemeldet. Die Prüfung sucht deshalb zusätzlich im
Syntaxbaum nach `CommandAst`-Knoten, deren Befehlsname ein Schlüsselwort ist. Genau das ist
die Signatur von `(if … )` in Argumentstellung.

**PSScriptAnalyzer mit begründeten Ausnahmen statt roher Zahl.**
318 Befunde beim ersten Lauf, davon 298 mal `Write-Host`. Das ist hier kein Mangel: die
Skripte sind Konsolenwerkzeuge, die formatierte Ausgabe ist das Ergebnis. Von den übrigen 20
waren 9 echt und sind behoben, 11 sind für dieses Projekt Fehlalarme. Die Ausnahmen stehen
einzeln begründet in `tools/PSScriptAnalyzerSettings.psd1` — eine Ausnahme ohne Begründung
höhlt die Prüfung aus.

Die echten Befunde:

* Fünf Nullvergleiche mit `$null` auf der rechten Seite. Bei einem Feld filtert
  `$x -ne $null`, statt zu vergleichen.
* `$profile` in `firewall-status.ps1` überschrieb eine automatische Variable.
* `$minAlter` in `kennwortrichtlinie.ps1` wurde ausgelesen, aber nie berichtet. Das
  Kriterium steht jetzt im Bericht: ohne Mindestalter lässt sich die Kennwortchronik
  aushebeln, indem man das Kennwort mehrfach hintereinander wechselt.
* Drei stumme `catch`-Blöcke protokollieren den Grund über `Write-Verbose`.

**Der param()-Block wird selbst gelesen.**
`System.Management.Automation` steht einem Projekt ohne Fremdbibliotheken nicht zur
Verfügung. `ParameterDienst` ist deshalb kein vollständiger PowerShell-Parser, sondern
beherrscht den Stil, in dem der Katalog geschrieben ist. Geprüft wurde er gegen den echten
Parser: bei allen **126 Parametern** stimmen Name, Typ, Pflichtangabe und `ValidateSet`
überein.

Dieser Vergleich hat sich gelohnt. Er deckte auf, dass verschachtelte Klammern — `[string[]]`
— sich nicht mit einem regulären Ausdruck greifen lassen; 22 Feldparameter kamen als
`object` an. Jetzt zählt ein Durchlauf die Klammern.

**Die Ausführung bleibt außerhalb.**
Der Grundsatz von Tag 1 steht: AdminWerk führt nichts aus. *In PowerShell öffnen* startet nur
die Sitzung im Skriptverzeichnis und legt den vorbereiteten Aufruf als Text hin — im Fenster
und in der Zwischenablage. Die Eingabetaste drückt ein Mensch. Bei Skripten mit
`adminRechte` wird die Sitzung über die Benutzerkontensteuerung angefordert, damit der Aufruf
nicht erst mittendrin an einer Berechtigung scheitert.

**Der Assistent ist zugeklappt voreingestellt.**
Aufgeklappt verdrängt er bei sieben Parametern den Quelltext vollständig aus dem Fenster —
und der ist der Hauptinhalt der Detailansicht. Die Kopfzeile nennt die Anzahl und lädt zum
Aufklappen ein.

### Oberflächentests — und der Runner als zweite Meinung

Zum Schluss wanderten die beiden Tests, mit denen die Oberfläche bis dahin von Hand
geprüft wurde, nach `tools/`: `oberflaechentest.ps1` (40 Einzelprüfungen) und
`alle-skripte-durchgehen.ps1` (jedes Skript des Katalogs einmal ausgewählt).

Die offene Frage war, ob UI-Automation auf einem GitHub-Runner überhaupt möglich ist. Sie
ist es: die Sitzung ist `UserInteractive`, hat `SessionId 2` und einen Bildschirm mit
1024×768. Die WPF-Anwendung öffnet dort ein Fenster, und die Automation sieht den Baum.
Der Auftrag braucht knapp drei Minuten und läuft neben den anderen beiden.

Der Runner hat sich dabei sofort bezahlt gemacht: 34 der 40 Prüfungen liefen durch, sechs
fielen — alle mit derselben Meldung, `Suche` sei kein bekannter Befehl. Ursache war eine
Closure über `.GetNewClosure()`: sie führt die **Variablen** des Skripts mit, aber nicht
zuverlässig seine **Funktionen**. Örtlich lief es trotzdem, auf dem Runner nicht. Ein
Fehler, den nur eine zweite Umgebung zeigt.

Gleich mit aufgefallen: auf dem Runner gibt es keine `favoriten.json`. Der Test legt beim
Favoritenklick eine an, und die Wiederherstellung sagte bis dahin nur „ohne Sicherung
nichts tun" — die Datei wäre liegen geblieben. Jetzt löscht der Test, was es vorher nicht
gab.

**Entscheidung: PSScriptAnalyzer prüft auch `tools/` mit.** Neue Werkzeuge sollen nicht
ungeprüft bleiben. Dabei zeigte sich, dass `-Path` nur einen Pfad annimmt: zwei Pfade als
Feld übergeben lässt das Cmdlet scheitern, die Variable bleibt leer, und der Schritt
meldet fälschlich „keine Befunde". Eine Prüfung, die nichts prüft und trotzdem grün ist,
ist schlimmer als keine. Jetzt zwei Durchläufe, gegen eine fehlerhafte Datei gegengeprüft.

### Geprüft

* `dotnet build` in `Release` mit `-warnaserror` — 0 Warnungen, 0 Fehler
* `katalog-pruefen.ps1` — 51 Skripte, keine Beanstandungen; gegen eine absichtlich
  beschädigte Kopie gegengeprüft, alle fünf eingeschleusten Fehler wurden gemeldet
* PSScriptAnalyzer mit dem Regelwerk — 0 Befunde; die Fehlerbehandlung des CI-Schritts
  ebenfalls gegen eine fehlerhafte Datei geprüft
* `ParameterDienst` gegen den PowerShell-Parser — 126 von 126 Parametern übereinstimmend
* Erzeugte Aufrufzeilen wurden **ausgeführt**, nicht nur angesehen: Felder werden korrekt
  aufgeteilt, Schalter binden als `SwitchParameter`, `O''Connor` kommt als `O'Connor` an
* Anwendung gestartet, Assistent über UI-Automation bedient, *In PowerShell öffnen*
  ausgelöst und die Befehlszeile des erzeugten Prozesses nachgelesen
* Beide Oberflächentests örtlich **und** auf dem GitHub-Runner — 40 von 40 Prüfungen,
  51 Skripte ohne Auffälligkeit

### Aufgefallen

* `$liste.Add("{0} {1}" -f $a, $b)` ist in PowerShell ein Aufruf mit zwei Argumenten: das
  Komma trennt die Methodenargumente, nicht die Formatwerte. Die Formatzeichenfolge bekommt
  nur `$a` und wirft. Es braucht eine zweite Klammer.
* `Resolve-Path -Relative` und die GitHub-Annotationssyntax vertragen sich gut — der CI-Lauf
  markiert Befunde direkt im Diff.
* Windows PowerShell 5.1 liest eine `.ps1` ohne BOM als ANSI. `oberflaechentest.ps1`
  vergleicht Beschriftungen der Oberfläche und braucht deshalb Umlaute — und damit ein BOM,
  sonst schlagen alle Vergleiche fehl. Dieselbe Regel, die schon für den `.ps1`-Export gilt.
* Ein Bildschirmfoto über `SetForegroundWindow` greift das falsche Fenster ab: Windows lässt
  Hintergrundprozesse den Fokus nicht stehlen. `PrintWindow` mit `PW_RENDERFULLCONTENT` holt
  die Fensterpixel unabhängig von der Stapelreihenfolge — und der aufrufende Prozess muss
  `SetProcessDPIAware` melden, sonst ist die Aufnahme bei Skalierung beschnitten.

### Als Nächstes

* [ ] Prüfpakete: mehrere Skripte auswählen und als Paket mit HTML-Bericht exportieren
* [ ] Katalog um weitere Bereiche erweitern: Drucker, Hyper-V, Zertifikate, Exchange
* [ ] Suchfeld über `Strg+F` erreichbar machen, Tastaturbedienung insgesamt schärfen
* [ ] Überlegen, ob rein lesende Skripte ihren Bericht in der Anwendung anzeigen dürfen —
      `catalog.json` bräuchte dafür ein Feld, das die CI gegenprüft

---

## Tag 2 — 20.09.2026

### Ergebnis

Der Katalog deckt jetzt alle zwölf geplanten Themenbereiche vollständig ab: **51 Skripte in
vier Kategorien**. Neu hinzugekommen ist die Kategorie **Konten**.

Dazu kamen im Lauf des Tages drei Dinge, die nicht geplant waren: eine **Favoritenfunktion**,
eine **eigene Bildmarke** samt Anwendungssymbol — und am Ende eine Runde Aufräumarbeit am
Repository selbst.

| | Vormittag | Abend |
|---|---|---|
| Skripte | 38 | 51 |
| Kategorien | 3 | 4 |
| Anwendungssymbol | keines | 16 bis 256 px |
| Favoriten | nein | ja, je Benutzer gespeichert |

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

### Nachtrag: Favoriten

Der Katalog ist mit 51 Skripten gross genug, dass die täglich gebrauchten Skripte untergehen.
Deshalb eine Favoritenfunktion:

* **Stern in der Liste** — jedes Skript lässt sich direkt in der Trefferliste markieren
* **Schaltfläche im Detailbereich** — beschriftet, damit die Funktion auffindbar ist
* **`Strg+D`** — schaltet das ausgewählte Skript um, egal wo der Fokus gerade steht
* **Eigener Reiter „Favoriten"** — steht direkt neben „Alle Skripte", mit Zähler in der Statusleiste

**Gespeichert wird je Benutzer, nicht im Projekt.**
`Services/FavoritenDienst` legt die Auswahl unter `%AppData%\AdminWerk\favoriten.json` ab — eine
schlichte Liste von Skript-IDs. Der Katalog gehört zur Anwendung und wird mit ihr aktualisiert;
die Favoriten gehören dem Benutzer und dürfen ein Update nicht verlieren. Ist die Datei
beschädigt oder nicht lesbar, startet die Anwendung mit leerer Auswahl statt mit einem Fehler.

`ScriptEintrag` implementiert dafür jetzt `INotifyPropertyChanged` — nur für `IstFavorit`, damit
der Stern sofort umschlägt, ohne die Liste neu aufzubauen.

### Dabei gefunden: Geisterpanel im Detailbereich

Mit der Favoritenansicht war zum ersten Mal ein Zustand erreichbar, in dem **kein** Skript
ausgewählt ist. Dabei kam ein Fehler zum Vorschein, der vorher nie sichtbar war: Der
Detailbereich blieb als leeres Gerüst stehen — Schaltflächen und leere Kennzeichen ohne Inhalt.

Ursache: `DataContext` und `Visibility` hingen am selben `Grid`.

```xml
<Grid Visibility="{Binding HatAuswahl, ...}"
      DataContext="{Binding AusgewaehltesSkript}">
```

Sobald `AusgewaehltesSkript` null ist, wird auch der `DataContext` null — und die
`Visibility`-Bindung läuft ins Leere statt gegen das ViewModel. WPF lässt das Element dann
einfach sichtbar. Die Bindung zeigt jetzt ausdrücklich auf das Fenster:

```xml
Visibility="{Binding DataContext.HatAuswahl,
                     RelativeSource={RelativeSource AncestorType=Window}, ...}"
```

Zusätzlich zeigt die leere Ansicht nun einen Hinweistext statt einer weissen Fläche — in der
Favoritenansicht mit der Anleitung, wie man Favoriten setzt.

### Geprüft (Favoriten)

Die Funktion wurde über UI Automation und Tastatureingabe am laufenden Fenster getestet,
nicht nur gebaut:

* Vorbereitete `favoriten.json` wird beim Start übernommen (goldene Sterne, Zähler stimmt)
* Klick auf den Listenstern schreibt die Datei — drei Klicks, drei neue IDs
* Schaltfläche im Detailbereich setzt und entfernt korrekt
* `Strg+D` schaltet das ausgewählte Skript um und speichert
* Nach Neustart der Anwendung ist die Auswahl unverändert vorhanden
* Fehlende `favoriten.json` führt zu leerer Auswahl, nicht zu einem Fehler

### Bildmarke und Anwendungssymbol

**Der erste Entwurf wurde verworfen.** Eine `Logo.png` im Projektverzeichnis enthielt das
Windows-Logo — eine Marke der Microsoft Corporation, die in einem Produktsymbol Dritter nichts
zu suchen hat, erst recht nicht in einem öffentlichen Repository. Dazu kamen drei handwerkliche
Punkte: kein Alphakanal (weisser Kasten auf dunklem Hintergrund), zu detailreich für 16–32 px
und der Schriftzug „Windows Administration **Toolkit**" statt „**Suite**". Die Datei wurde
deshalb weder eingebunden noch committet.

**Der zweite Entwurf, eine blaue Kachel mit `>_`, wurde ebenfalls verworfen** — und das war der
lehrreichere Fehler. Er war technisch einwandfrei: zwei Formen, bei 16 px lesbar, keine fremde
Marke. Nur sieht genau so das Symbol von PowerShell aus. Ein Werkzeug, das in der Taskleiste
direkt neben PowerShell liegt, darf nicht wie PowerShell aussehen. Aus „enthält keine fremde
Marke" folgt eben noch nicht „ist unterscheidbar".

**Die gewählte Marke:** ein Sechskant im Blauverlauf der Anwendung mit einem „A" in Segoe UI
Bold. Der Sechskant steht für „Werk" — Handwerk, Technik —, das A für AdminWerk. Der Umriss
unterscheidet sich schon auf den ersten Blick von den Quadraten und Kacheln der übrigen
Entwicklerwerkzeuge.

Fünf Entwürfe wurden dafür nebeneinander in den Grössen 160/48/32/24/16 px gerendert, jeweils
auf hellem und auf dunklem Grund. Ohne diesen Vergleich wäre die Ähnlichkeit zu PowerShell
nicht aufgefallen — bei 256 px sieht fast jeder Entwurf gut aus.

**Erzeugung:** `tools/logo-erzeugen.py` (Python mit Pillow) erzeugt alle Dateien reproduzierbar.
Rand und Buchstabengrösse werden je Symbolgrösse nachgeführt: bei 16 px bleibt fast kein Rand,
sonst würde die Marke zu viel Fläche verschenken. Die `.ico`-Datei wird selbst zusammengesetzt,
weil sie sieben Grössen von 16 bis 256 px enthalten soll und jede davon einzeln gezeichnet wird,
statt aus einer grossen Fassung heruntergerechnet zu werden.

Eingebunden über `ApplicationIcon` (Symbol der EXE) und zusätzlich als `Resource` samt
`Icon="Themes/adminwerk.ico"` am Fenster. Geprüft wurde beides: Das Symbol liess sich mit
`ExtractIconEx` aus der gebauten EXE holen (48 px und 24 px), und die Titelleiste des laufenden
Fensters zeigt es.

Die README trägt jetzt eine Wortmarke im Kopf, in zwei Fassungen — sonst verschwindet „Admin"
im hellen Thema von GitHub. Die Auswahl übernimmt `<picture>` mit `prefers-color-scheme`.

### Zum Schluss: ein Commit, der sich nicht vertreiben liess

Das Repository sollte nur einen Mitwirkenden ausweisen. Der allererste Commit von Tag 1 trug
jedoch eine Zeile `Co-Authored-By:` am Ende der Nachricht, und GitHub führte daraufhin zwei
Personen unter „Contributors".

**Erster Versuch: Nachricht korrigieren.** `git commit --amend` ohne die Zeile, danach
`git push --force-with-lease`. Der Verlauf war damit sauber — und die Seite zeigte weiterhin
zwei Mitwirkende.

**Zweiter Versuch: abwarten.** Drei weitere Commits wurden gepusht. Die Anzeige blieb.

**Die Ursache** liess sich erst mit einem Blick auf die verschiedenen Datenquellen finden:

| Quelle | Antwort |
|---|---|
| `git log` lokal | 4 Commits, überall nur ein Autor, keine Co-Author-Zeile |
| `/repos/.../commits?sha=main` | dieselben 4 Commits, nur ein Autor |
| `/repos/.../stats/contributors` | `alikiratli total=4` — korrekt |
| `/repos/.../contributors` | `alikiratli commits=1` — veraltet |
| Seitenleiste im Browser | **2 Mitwirkende** |

Die entscheidende Abfrage war dann `/repos/.../commits/5020c27`: **Der ursprüngliche Commit
lag noch auf dem Server.** Ein `--force`-Push nimmt einen Commit aus dem Verlauf des Zweiges,
löscht das Objekt aber nicht — es bleibt über seine Prüfsumme erreichbar, und die
zwischengespeicherte Mitwirkendenliste speiste sich weiter daraus.

Gelernt: Ein Commit ist nach `--force` **aus dem Verlauf** verschwunden, nicht **vom Server**.
Wer eine Nachricht wirklich aus einem öffentlichen Repository entfernen will, muss entweder den
Support bemühen oder das Repository neu anlegen. Und: Wenn die Oberfläche etwas anderes sagt
als die API, hat meistens nicht die Oberfläche unrecht, sondern die eine Abfrage, die man
gerade nicht gestellt hat.

**Behoben** durch Neuanlage des Repositories: Verlauf als `git bundle` gesichert und mit
`git bundle verify` geprüft, Einstellungen notiert, Repository gelöscht und unter demselben
Namen neu angelegt, dieselben vier Commits gepusht. Danach liefert `/commits/5020c27` ein
`422 No commit found`, die Contributors-Liste nennt `alikiratli commits=4`, und die Seite zeigt
einen Mitwirkenden.

Verloren ging dabei nichts: null Sterne, null Forks, null Beobachter. Nur das Anlagedatum des
Repositories ist jetzt der heutige Tag, und die Commit-Prüfsummen sind unverändert geblieben.

### Als Nächstes

* [x] ~~Skripte als Favoriten markieren können~~ — erledigt
* [x] ~~Anwendungssymbol (`.ico`) ergänzen~~ — erledigt
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
