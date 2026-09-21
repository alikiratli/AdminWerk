using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using AdminWerk.Models;
using AdminWerk.Services;
using Microsoft.Win32;

namespace AdminWerk.ViewModels;

/// <summary>ViewModel des Hauptfensters: Kategorienavigation, Suche und Skriptaktionen.</summary>
public sealed class HauptViewModel : ViewModelBasis
{
    /// <summary>Pseudokategorie, die alle Skripte zusammenfasst.</summary>
    public const string AlleKategorienId = "*";

    /// <summary>Pseudokategorie, die nur die Favoriten des Benutzers zeigt.</summary>
    public const string FavoritenKategorieId = "+";

    private readonly KatalogDienst _katalogDienst;
    private readonly FavoritenDienst _favoritenDienst;
    private readonly PaketDienst _paketDienst;
    private readonly List<ScriptEintrag> _alleSkripte = [];

    private int _echteKategorien;

    private ScriptKategorie? _ausgewaehlteKategorie;
    private ScriptEintrag? _ausgewaehltesSkript;
    private string _suchbegriff = string.Empty;
    private string _statusmeldung = string.Empty;
    private string? _ladefehler;
    private string _aufrufzeile = string.Empty;

    public HauptViewModel() : this(new KatalogDienst(), new FavoritenDienst())
    {
    }

    public HauptViewModel(KatalogDienst katalogDienst, FavoritenDienst favoritenDienst)
    {
        _katalogDienst = katalogDienst;
        _favoritenDienst = favoritenDienst;
        _paketDienst = new PaketDienst(katalogDienst.SkriptVerzeichnis);

        KopierenBefehl = new AktionsBefehl(_ => SkriptKopieren(), _ => AusgewaehltesSkript is not null);
        SpeichernBefehl = new AktionsBefehl(_ => SkriptSpeichern(), _ => AusgewaehltesSkript is not null);
        SkriptordnerOeffnenBefehl = new AktionsBefehl(_ => SkriptordnerOeffnen());
        SucheLeerenBefehl = new AktionsBefehl(_ => Suchbegriff = string.Empty,
            _ => !string.IsNullOrEmpty(Suchbegriff));
        NeuLadenBefehl = new AktionsBefehl(_ => KatalogLaden());
        FavoritUmschaltenBefehl = new AktionsBefehl(FavoritUmschalten, p => (p ?? AusgewaehltesSkript) is not null);
        AufrufKopierenBefehl = new AktionsBefehl(_ => AufrufKopieren(), _ => HatParameter);
        InPowerShellOeffnenBefehl = new AktionsBefehl(_ => InPowerShellOeffnen(), _ => AusgewaehltesSkript is not null);
        PaketErzeugenBefehl = new AktionsBefehl(_ => PaketErzeugen(), _ => PaketAnzahl > 0);
        PaketLeerenBefehl = new AktionsBefehl(_ => PaketLeeren(), _ => PaketAnzahl > 0);
        ParameterLeerenBefehl = new AktionsBefehl(_ => ParameterLeeren(), _ => HatParameter);

        KatalogLaden();
    }

    public ObservableCollection<ScriptKategorie> Kategorien { get; } = [];

    public ObservableCollection<ScriptEintrag> GefilterteSkripte { get; } = [];

    public AktionsBefehl KopierenBefehl { get; }

    public AktionsBefehl SpeichernBefehl { get; }

    public AktionsBefehl SkriptordnerOeffnenBefehl { get; }

    public AktionsBefehl SucheLeerenBefehl { get; }

    public AktionsBefehl NeuLadenBefehl { get; }

    public AktionsBefehl FavoritUmschaltenBefehl { get; }

    public AktionsBefehl AufrufKopierenBefehl { get; }

    public AktionsBefehl ParameterLeerenBefehl { get; }

    public AktionsBefehl InPowerShellOeffnenBefehl { get; }

    public AktionsBefehl PaketErzeugenBefehl { get; }

    public AktionsBefehl PaketLeerenBefehl { get; }

    public int PaketAnzahl => _alleSkripte.Count(s => s.ImPaket);

    public bool HatPaket => PaketAnzahl > 0;

    public string PaketText => PaketAnzahl == 1 ? "1 Skript im Paket" : $"{PaketAnzahl} Skripte im Paket";

    public ScriptKategorie? AusgewaehlteKategorie
    {
        get => _ausgewaehlteKategorie;
        set
        {
            if (SetzeFeld(ref _ausgewaehlteKategorie, value))
            {
                FilterAnwenden();
            }
        }
    }

    public ScriptEintrag? AusgewaehltesSkript
    {
        get => _ausgewaehltesSkript;
        set
        {
            if (SetzeFeld(ref _ausgewaehltesSkript, value))
            {
                BenachrichtigeAenderung(nameof(HatAuswahl));
                Statusmeldung = string.Empty;
                ParameterUebernehmen();
            }
        }
    }

    public bool HatAuswahl => AusgewaehltesSkript is not null;

    /// <summary>Parameter des ausgewaehlten Skripts, mit den Eingaben des Benutzers.</summary>
    public ObservableCollection<SkriptParameter> Parameter { get; } = [];

    public bool HatParameter => Parameter.Count > 0;

    public string ParameterUeberschrift => Parameter.Count == 1
        ? "Parameter (1)"
        : $"Parameter ({Parameter.Count})";

    /// <summary>Der fertige Aufruf, wie er in die PowerShell gehoert.</summary>
    public string Aufrufzeile => _aufrufzeile;

    /// <summary>Namen der Pflichtparameter, die noch leer sind - sonst leer.</summary>
    public string FehlendeAngaben
    {
        get
        {
            var offen = Parameter
                .Where(p => p.IstPflicht && !p.IstSchalter && p.Wert.Trim().Length == 0)
                .Select(p => p.Name)
                .ToList();

            return offen.Count == 0
                ? string.Empty
                : "Noch ohne Wert: " + string.Join(", ", offen);
        }
    }

    public bool HatFehlendeAngaben => FehlendeAngaben.Length > 0;

    public string Suchbegriff
    {
        get => _suchbegriff;
        set
        {
            if (SetzeFeld(ref _suchbegriff, value))
            {
                FilterAnwenden();
            }
        }
    }

    public string Statusmeldung
    {
        get => _statusmeldung;
        private set => SetzeFeld(ref _statusmeldung, value);
    }

    /// <summary>Fehlertext, falls der Katalog nicht gelesen werden konnte; sonst <c>null</c>.</summary>
    public string? Ladefehler
    {
        get => _ladefehler;
        private set
        {
            if (SetzeFeld(ref _ladefehler, value))
            {
                BenachrichtigeAenderung(nameof(HatLadefehler));
            }
        }
    }

    public bool HatLadefehler => !string.IsNullOrEmpty(Ladefehler);

    public string TrefferText => GefilterteSkripte.Count == 1
        ? "1 Skript"
        : $"{GefilterteSkripte.Count} Skripte";

    public string KatalogInfo => $"{_alleSkripte.Count} Skripte in {_echteKategorien} Kategorien";

    public int FavoritenAnzahl => _alleSkripte.Count(s => s.IstFavorit);

    /// <summary>True, wenn die aktuelle Ansicht kein einziges Skript enthaelt.</summary>
    public bool KeineTreffer => GefilterteSkripte.Count == 0 && !HatLadefehler;

    /// <summary>Hinweistext fuer die leere Ansicht - in der Favoritenansicht mit Anleitung.</summary>
    public string Leermeldung =>
        AusgewaehlteKategorie?.Id == FavoritenKategorieId && Suchbegriff.Trim().Length == 0
            ? "Noch keine Favoriten.\n\nMarkieren Sie ein Skript mit dem Stern ☆\nin der Liste oder mit Strg+D."
            : "Keine Skripte gefunden.";

    private void KatalogLaden()
    {
        var vorherigeKategorieId = AusgewaehlteKategorie?.Id;

        // Beim Neuladen entstehen neue Objekte - die alten Anmeldungen muessen weg,
        // sonst zaehlt die Paketanzahl Skripte mit, die es nicht mehr gibt.
        foreach (var alt in _alleSkripte)
        {
            alt.PropertyChanged -= SkriptGeaendert;
        }

        _alleSkripte.Clear();
        Kategorien.Clear();

        try
        {
            var katalog = _katalogDienst.Laden();
            _alleSkripte.AddRange(katalog.Skripte);

            Kategorien.Add(new ScriptKategorie
            {
                Id = AlleKategorienId,
                Name = "Alle Skripte",
                Beschreibung = "Der vollständige Katalog über alle Bereiche hinweg.",
                Symbol = "◆"
            });

            Kategorien.Add(new ScriptKategorie
            {
                Id = FavoritenKategorieId,
                Name = "Favoriten",
                Beschreibung = "Die Skripte, die Sie mit dem Stern markiert haben.",
                Symbol = "★"
            });

            foreach (var kategorie in katalog.Kategorien)
            {
                Kategorien.Add(kategorie);
            }

            var namenNachId = katalog.Kategorien.ToDictionary(k => k.Id, k => k.Name);
            foreach (var skript in _alleSkripte)
            {
                skript.KategorieName = namenNachId.TryGetValue(skript.KategorieId, out var name)
                    ? name
                    : skript.KategorieId;
            }

            // Gespeicherte Favoritenauswahl auf die frisch geladenen Skripte uebertragen.
            var favoriten = _favoritenDienst.Laden();
            foreach (var skript in _alleSkripte)
            {
                skript.IstFavorit = favoriten.Contains(skript.Id);
                skript.PropertyChanged += SkriptGeaendert;
            }

            _echteKategorien = katalog.Kategorien.Count;
            Ladefehler = null;
        }
        catch (Exception ex)
        {
            Ladefehler = $"Der Skriptkatalog konnte nicht geladen werden: {ex.Message}";
        }

        AusgewaehlteKategorie = Kategorien.FirstOrDefault(k => k.Id == vorherigeKategorieId)
                                ?? Kategorien.FirstOrDefault();

        BenachrichtigeAenderung(nameof(KatalogInfo));
        FilterAnwenden();
    }

    private void FilterAnwenden()
    {
        var kategorieId = AusgewaehlteKategorie?.Id ?? AlleKategorienId;
        var suche = Suchbegriff.Trim().ToLowerInvariant();

        var treffer = _alleSkripte
            .Where(s => kategorieId switch
            {
                AlleKategorienId      => true,
                FavoritenKategorieId  => s.IstFavorit,
                _                     => s.KategorieId == kategorieId
            })
            .Where(s => suche.Length == 0 || s.Suchtext.Contains(suche, StringComparison.Ordinal))
            .OrderBy(s => s.Titel, StringComparer.CurrentCulture);

        var vorherigeAuswahlId = AusgewaehltesSkript?.Id;

        GefilterteSkripte.Clear();
        foreach (var skript in treffer)
        {
            GefilterteSkripte.Add(skript);
        }

        AusgewaehltesSkript = GefilterteSkripte.FirstOrDefault(s => s.Id == vorherigeAuswahlId)
                              ?? GefilterteSkripte.FirstOrDefault();

        BenachrichtigeAenderung(nameof(TrefferText));
        BenachrichtigeAenderung(nameof(KeineTreffer));
        BenachrichtigeAenderung(nameof(Leermeldung));
    }

    /// <summary>
    /// Markiert ein Skript als Favorit oder nimmt die Markierung zurueck.
    /// Der Parameter kommt aus der Liste; ohne Parameter gilt die aktuelle Auswahl.
    /// </summary>
    private void FavoritUmschalten(object? parameter)
    {
        if ((parameter as ScriptEintrag ?? AusgewaehltesSkript) is not { } skript)
        {
            return;
        }

        skript.IstFavorit = !skript.IstFavorit;

        var fehler = _favoritenDienst.Speichern(_alleSkripte.Where(s => s.IstFavorit).Select(s => s.Id));

        Statusmeldung = fehler is null
            ? skript.IstFavorit
                ? $"„{skript.Titel}“ zu den Favoriten hinzugefügt."
                : $"„{skript.Titel}“ aus den Favoriten entfernt."
            : $"Favoriten konnten nicht gespeichert werden: {fehler}";

        BenachrichtigeAenderung(nameof(FavoritenAnzahl));

        // In der Favoritenansicht verschwindet ein abgewähltes Skript sofort aus der Liste.
        if (AusgewaehlteKategorie?.Id == FavoritenKategorieId)
        {
            FilterAnwenden();
        }
    }

    private void SkriptGeaendert(object? absender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(ScriptEintrag.ImPaket))
        {
            return;
        }

        BenachrichtigeAenderung(nameof(PaketAnzahl));
        BenachrichtigeAenderung(nameof(HatPaket));
        BenachrichtigeAenderung(nameof(PaketText));

        // AktionsBefehl haengt an CommandManager.RequerySuggested. Der Haken wird zwar
        // ueber die Oberflaeche gesetzt, "Paket leeren" aendert ihn aber im Code -
        // danach muss die Ausfuehrbarkeit ausdruecklich neu bewertet werden.
        CommandManager.InvalidateRequerySuggested();
    }

    private void PaketLeeren()
    {
        foreach (var skript in _alleSkripte)
        {
            skript.ImPaket = false;
        }

        Statusmeldung = "Paketauswahl geleert.";
    }

    /// <summary>
    /// Schreibt die ausgewaehlten Skripte als Pruefpaket in einen Ordner: die Dateien,
    /// den Laeufer und die Beschreibung. Ausgefuehrt wird nichts.
    /// </summary>
    private void PaketErzeugen()
    {
        var gewaehlt = _alleSkripte.Where(s => s.ImPaket).ToList();
        if (gewaehlt.Count == 0)
        {
            return;
        }

        var dialog = new OpenFolderDialog
        {
            Title = "Wohin soll das Prüfpaket?",
            Multiselect = false
        };

        if (dialog.ShowDialog() != true)
        {
            return;
        }

        var name = $"AdminWerk-Pruefpaket_{DateTime.Now:yyyy-MM-dd_HHmm}";
        var ziel = Path.Combine(dialog.FolderName, name);

        try
        {
            var anzahl = _paketDienst.Erzeugen(ziel, "Prüfpaket", gewaehlt);

            var fehlend = gewaehlt.Count - anzahl;
            Statusmeldung = fehlend == 0
                ? $"Prüfpaket mit {anzahl} Skripten erstellt: {ziel}"
                : $"Prüfpaket mit {anzahl} Skripten erstellt; {fehlend} Datei(en) fehlten im Katalog.";

            Process.Start(new ProcessStartInfo(ziel) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Statusmeldung = $"Prüfpaket konnte nicht erstellt werden: {ex.Message}";
        }
    }

    /// <summary>Liest den param()-Block des ausgewaehlten Skripts und baut den Assistenten neu auf.</summary>
    private void ParameterUebernehmen()
    {
        foreach (var alt in Parameter)
        {
            alt.PropertyChanged -= ParameterGeaendert;
        }

        Parameter.Clear();

        if (AusgewaehltesSkript is { } skript)
        {
            foreach (var p in ParameterDienst.Auslesen(skript.Inhalt))
            {
                p.PropertyChanged += ParameterGeaendert;
                Parameter.Add(p);
            }
        }

        BenachrichtigeAenderung(nameof(HatParameter));
        BenachrichtigeAenderung(nameof(ParameterUeberschrift));
        AufrufzeileNeuBauen();
    }

    private void ParameterGeaendert(object? absender, PropertyChangedEventArgs e) => AufrufzeileNeuBauen();

    private void AufrufzeileNeuBauen()
    {
        _aufrufzeile = AusgewaehltesSkript is { } skript
            ? ParameterDienst.Aufrufzeile(skript.Datei, Parameter)
            : string.Empty;

        BenachrichtigeAenderung(nameof(Aufrufzeile));
        BenachrichtigeAenderung(nameof(FehlendeAngaben));
        BenachrichtigeAenderung(nameof(HatFehlendeAngaben));
    }

    private void ParameterLeeren()
    {
        foreach (var p in Parameter)
        {
            p.Zuruecksetzen();
        }

        Statusmeldung = "Eingaben zurückgesetzt.";
    }

    private void AufrufKopieren()
    {
        try
        {
            Clipboard.SetText(Aufrufzeile);
            Statusmeldung = "Aufrufzeile in die Zwischenablage kopiert.";
        }
        catch (Exception ex)
        {
            Statusmeldung = $"Kopieren fehlgeschlagen: {ex.Message}";
        }
    }

    private void SkriptKopieren()
    {
        if (AusgewaehltesSkript is null)
        {
            return;
        }

        try
        {
            Clipboard.SetText(AusgewaehltesSkript.Inhalt);
            Statusmeldung = "In die Zwischenablage kopiert.";
        }
        catch (Exception ex)
        {
            Statusmeldung = $"Kopieren fehlgeschlagen: {ex.Message}";
        }
    }

    private void SkriptSpeichern()
    {
        if (AusgewaehltesSkript is null)
        {
            return;
        }

        var dialog = new SaveFileDialog
        {
            Title = "Skript speichern",
            FileName = $"{AusgewaehltesSkript.Id}.ps1",
            DefaultExt = ".ps1",
            Filter = "PowerShell-Skript (*.ps1)|*.ps1|Alle Dateien (*.*)|*.*"
        };

        if (dialog.ShowDialog() != true)
        {
            return;
        }

        try
        {
            // UTF-8 mit BOM, damit die Windows PowerShell 5.1 Umlaute korrekt liest.
            File.WriteAllText(dialog.FileName, AusgewaehltesSkript.Inhalt, new System.Text.UTF8Encoding(true));
            Statusmeldung = $"Gespeichert: {dialog.FileName}";
        }
        catch (Exception ex)
        {
            Statusmeldung = $"Speichern fehlgeschlagen: {ex.Message}";
        }
    }

    /// <summary>
    /// Oeffnet eine PowerShell-Sitzung im Skriptverzeichnis und legt den vorbereiteten
    /// Aufruf bereit - ausgefuehrt wird nichts.
    /// </summary>
    /// <remarks>
    /// Der bewusste Verzicht auf eine eingebaute Ausfuehrung bleibt bestehen: AdminWerk
    /// startet nur die Sitzung. Was darin passiert, entscheidet der Mensch davor, nachdem
    /// er den Quelltext gelesen hat. Gebraucht ein Skript erhoehte Rechte, wird die
    /// Sitzung ueber die Benutzerkontensteuerung angefordert - sonst scheitert der Aufruf
    /// erst spaeter und unverstaendlich.
    /// </remarks>
    private void InPowerShellOeffnen()
    {
        if (AusgewaehltesSkript is not { } skript)
        {
            return;
        }

        var pfad = _katalogDienst.SkriptPfad(skript);
        if (!File.Exists(pfad))
        {
            Statusmeldung = $"Skriptdatei nicht gefunden: {pfad}";
            return;
        }

        var verzeichnis = Path.GetDirectoryName(pfad) ?? _katalogDienst.SkriptVerzeichnis;
        var aufruf = Aufrufzeile.Length > 0
            ? Aufrufzeile
            : ".\\" + Path.GetFileName(pfad);

        var befehl = string.Join("; ",
            $"Set-Location -LiteralPath {PsZeichenkette(verzeichnis)}",
            $"Write-Host ''",
            $"Write-Host {PsZeichenkette("AdminWerk – " + skript.Titel)} -ForegroundColor Cyan",
            $"Write-Host {PsZeichenkette(skript.Datei)} -ForegroundColor DarkGray",
            $"Write-Host ''",
            $"Write-Host {PsZeichenkette("Vorbereiteter Aufruf (liegt auch in der Zwischenablage):")} -ForegroundColor DarkGray",
            $"Write-Host {PsZeichenkette("  " + aufruf)} -ForegroundColor Yellow",
            $"Write-Host ''",
            $"Write-Host {PsZeichenkette("Es wurde nichts ausgeführt. Bitte den Quelltext vorher lesen.")} -ForegroundColor DarkGray",
            $"Write-Host ''");

        try
        {
            Clipboard.SetText(aufruf);
        }
        catch (Exception)
        {
            // Die Zwischenablage ist nur eine Bequemlichkeit - die Sitzung startet trotzdem.
        }

        var start = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = true,
            WorkingDirectory = verzeichnis
        };

        start.ArgumentList.Add("-NoExit");
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add(befehl);

        if (skript.AdminRechte)
        {
            start.Verb = "runas";
        }

        try
        {
            Process.Start(start);
            Statusmeldung = skript.AdminRechte
                ? "PowerShell als Administrator geöffnet – das Skript wurde nicht ausgeführt."
                : "PowerShell geöffnet – das Skript wurde nicht ausgeführt.";
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            // 1223 = der Benutzer hat die Rechteanforderung abgelehnt
            Statusmeldung = "Die Anforderung erhöhter Rechte wurde abgebrochen.";
        }
        catch (Exception ex)
        {
            Statusmeldung = $"PowerShell konnte nicht geöffnet werden: {ex.Message}";
        }
    }

    /// <summary>Verpackt einen Wert als einfach zitierte PowerShell-Zeichenkette.</summary>
    private static string PsZeichenkette(string wert) => "'" + wert.Replace("'", "''") + "'";

    private void SkriptordnerOeffnen()
    {
        try
        {
            Process.Start(new ProcessStartInfo(_katalogDienst.SkriptVerzeichnis) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Statusmeldung = $"Ordner konnte nicht geöffnet werden: {ex.Message}";
        }
    }
}
