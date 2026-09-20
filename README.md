# AdminWerk — Windows Administration Suite

Eine WPF-Anwendung, die geprüfte PowerShell-Skripte für die tägliche Windows-Administration
bereitstellt. Kategorisiert, durchsuchbar, mit Syntaxhervorhebung — und mit einem Klick in der
Zwischenablage oder als `.ps1`-Datei gespeichert.

![AdminWerk Hauptfenster](docs/bilder/adminwerk-hauptfenster.png)

---

## Warum AdminWerk?

Wer Windows-Systeme betreut, schreibt dieselben Skripte immer wieder: Speicherplatz prüfen,
Dienste überwachen, den Patchstand ermitteln, ein Sicherheits-Audit fahren. AdminWerk sammelt
diese Skripte an einem Ort — sauber dokumentiert, mit Hinweisen zu benötigten Rechten und
Modulen, sofort einsatzbereit.

**Die Anwendung führt keine Skripte aus.** Sie stellt sie zur Verfügung; ausgeführt werden sie
bewusst von Hand in einer PowerShell-Sitzung, in der die Administratorin oder der Administrator
den Inhalt vorher gelesen hat.

---

## Funktionen

| Funktion | Beschreibung |
|---|---|
| **Kategorien** | System, Netzwerk und Security als eigene Bereiche, dazu eine Gesamtansicht |
| **Volltextsuche** | Durchsucht Titel, Beschreibung, Schlagwörter **und** den Skriptinhalt |
| **Syntaxhervorhebung** | PowerShell-Quelltext farblich aufbereitet (Kommentare, Cmdlets, Variablen, Parameter) |
| **Zwischenablage** | Das vollständige Skript mit einem Klick kopieren |
| **Als `.ps1` speichern** | Export mit UTF-8-BOM, damit Windows PowerShell 5.1 die Umlaute korrekt liest |
| **Kennzeichnung** | Jedes Skript zeigt Kategorie, benötigte Rechte und Voraussetzungen |
| **Erweiterbar** | Eigene Skripte im Ordner `Scripts` ergänzen, `catalog.json` pflegen, „Neu laden“ klicken |

---

## Skriptkatalog

Aktuell **38 Skripte** in drei Bereichen.

### ▣ System (13)

| Skript | Zweck |
|---|---|
| Freien Speicherplatz prüfen | Schwellenwertprüfung aller Datenträger mit Protokollierung |
| HTML-Bericht zur Datenträgerbelegung | Farbig aufbereiteter Bericht über mehrere Computer |
| Systemdateien prüfen und reparieren | DISM und SFC in der empfohlenen Reihenfolge |
| Letzter Neustart und Betriebsdauer | Uptime mit Neustartempfehlung |
| Ausstehenden Neustart erkennen | CBS, Windows Update, Dateiumbenennungen, Computerumbenennung |
| Kritische Ereignisse im Ereignisprotokoll | Gruppiert nach Quelle und Ereignis-ID |
| Kritische Dienste überwachen und starten | Automatischer Neustart gestoppter Dienste mit Protokoll |
| Starttypen der Dienste gegen Soll prüfen | Deckt Abweichungen auf, die erst beim Neustart auffallen |
| Patchstand und ausstehende Updates | Hotfix-Historie plus Windows-Update-Abfrage |
| Software-Inventar erstellen | Aus der Registrierung statt über `Win32_Product` |
| Hardware-Inventar erfassen | Seriennummer, Modell, CPU, RAM, BIOS, Netzwerk |
| Geplante Aufgaben prüfen | Fehlgeschlagene, deaktivierte und privilegierte Aufgaben |
| Prozesse mit höchster CPU- und RAM-Last | Echte CPU-Messung über zwei Messpunkte |

### ◎ Netzwerk (10)

| Skript | Zweck |
|---|---|
| Netzwerkdiagnose in einem Durchlauf | Adapter → IP → Gateway → DNS → Auflösung → Internet |
| Netzwerkadapter und IP-Konfiguration | Adapter, IP, Gateway, DNS und Treiber je Schnittstelle |
| TCP-Ports auf Erreichbarkeit testen | Ziel-/Port-Matrix mit Zeitlimit und Dienstnamen |
| Namensauflösung gegen mehrere DNS-Server | Findet abweichende Antworten zwischen Servern |
| Windows-DNS-Server prüfen | Dienst, Zonen, Weiterleitungen, Stichprobe |
| DHCP-Bereiche und Auslastung | Belegung in Prozent, abgelaufene Leases |
| Lauschende Ports mit Prozesszuordnung | Welches Programm hat welchen Port geöffnet |
| Route verfolgen und Latenz messen | Hebt den Sprung mit dem größten Latenzzuwachs hervor |
| Aktive Firewall-Regeln auswerten | Eingehende Erlaubnisregeln mit Port, Quelle und Programm |
| SMB-Freigaben und Berechtigungen | Freigabe- und NTFS-Rechte plus aktive Sitzungen |

### ⬟ Security (15)

| Skript | Zweck |
|---|---|
| **Vollständige Sicherheitsprüfung mit Bewertung** | Alle Kernprüfungen in einem Lauf, Punktzahl 0–10 |
| Microsoft Defender — Status und Ausschlüsse | Echtzeitschutz, Signaturen, Manipulationsschutz, Ausschlüsse |
| Firewall-Profile und Standardverhalten | Alle drei Profile inklusive Protokollierung |
| BitLocker-Verschlüsselung prüfen | Schutzstatus und Schlüsselschutzvorrichtungen |
| Lokale Administratoren auflisten | Über die SID — sprachunabhängig |
| Gast- und Standardkonten prüfen | Konten mit SID-Endung `-500` und `-501` |
| RDP-Konfiguration prüfen | Port, NLA, Sicherheitsstufe, Berechtigte, Firewall |
| Fehlgeschlagene Anmeldungen auswerten | Erkennt Brute Force und Password Spraying |
| Letzte erfolgreiche Anmeldungen | Ohne das Rauschen der Dienstanmeldungen |
| Autostart-Programme prüfen | Markiert Einträge außerhalb üblicher Programmverzeichnisse |
| Verdächtige Dienste aufspüren | Ungequotete Pfade, fehlende Signaturen |
| Kennwort- und Sperrrichtlinie prüfen | Lokal und in der Domäne, mit Bewertung |
| Inaktive AD-Konten finden | Benutzer und Computer ohne Anmeldung seit X Tagen |
| Privilegierte AD-Gruppen prüfen | Domänen-, Organisations-, Schema-Admins, rekursiv |
| Bald ablaufende AD-Kennwörter | Mit Vorlaufzeit und CSV-Export für den Servicedesk |

---

## Installation

### Voraussetzungen

* Windows 10 / 11 oder Windows Server 2016 und neuer
* [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) (zum Ausführen)
* [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) oder neuer (zum Bauen)

### Bauen und starten

```powershell
git clone https://github.com/alikiratli/AdminWerk.git
cd AdminWerk
dotnet build
dotnet run --project src\AdminWerk
```

### Eigenständige Datei erzeugen

```powershell
dotnet publish src\AdminWerk -c Release -r win-x64 --self-contained false -o veroeffentlichung
```

---

## Eigene Skripte ergänzen

1. Die `.ps1`-Datei unter `src/AdminWerk/Scripts/<kategorie>/` ablegen.
2. In `src/AdminWerk/Scripts/catalog.json` einen Eintrag ergänzen:

```json
{
  "id": "sys-mein-skript",
  "kategorie": "system",
  "titel": "Mein Skript",
  "beschreibung": "Was das Skript tut.",
  "datei": "system/mein-skript.ps1",
  "tags": ["Beispiel"],
  "adminRechte": true,
  "voraussetzung": "Windows 10/11"
}
```

3. In der Anwendung auf **Neu laden** klicken — ein Neustart ist nicht nötig.

Die Schaltfläche **Skriptordner** öffnet das Verzeichnis direkt im Explorer.

---

## Projektaufbau

```
AdminWerk/
├── AdminWerk.sln
├── README.md
├── docs/
│   ├── FORTSCHRITT.md          Entwicklungstagebuch
│   └── bilder/
└── src/AdminWerk/
    ├── AdminWerk.csproj
    ├── App.xaml(.cs)           Anwendungseinstieg, deutsche Kultur
    ├── MainWindow.xaml(.cs)    Hauptfenster
    ├── Models/                 ScriptEintrag, ScriptKategorie, ScriptKatalog
    ├── Services/               KatalogDienst — liest catalog.json und die .ps1-Dateien
    ├── ViewModels/             HauptViewModel, AktionsBefehl, ViewModelBasis
    ├── Views/                  PowerShellHervorhebung — Syntaxeinfärbung
    ├── Themes/                 Palette.xaml, Steuerelemente.xaml
    └── Scripts/
        ├── catalog.json
        ├── system/
        ├── netzwerk/
        └── security/
```

Die Anwendung ist nach MVVM aufgebaut und kommt ohne Fremdbibliotheken aus.

---

## Hinweise zum Einsatz

* **Skripte vor der Ausführung lesen.** Jedes Skript hat einen Kommentarkopf mit `.SYNOPSIS`,
  `.DESCRIPTION` und `.EXAMPLE`.
* **Erst prüfen, dann ändern.** Skripte, die etwas verändern, besitzen einen Schalter wie
  `-NurPruefen`. Im Zweifel damit beginnen.
* **Administratorrechte.** Die Kennzeichnung im Detailbereich weist aus, ob eine erhöhte
  PowerShell-Sitzung nötig ist.
* **Alle Skripte sind gegen den Parser von Windows PowerShell 5.1 geprüft** und kommen ohne
  Syntax aus, die erst ab PowerShell 7 verfügbar ist.

---

## Lizenz

MIT — siehe [LICENSE](LICENSE).
