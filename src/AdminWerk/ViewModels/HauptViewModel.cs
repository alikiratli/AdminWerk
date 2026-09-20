using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
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
    private readonly List<ScriptEintrag> _alleSkripte = [];

    private int _echteKategorien;

    private ScriptKategorie? _ausgewaehlteKategorie;
    private ScriptEintrag? _ausgewaehltesSkript;
    private string _suchbegriff = string.Empty;
    private string _statusmeldung = string.Empty;
    private string? _ladefehler;

    public HauptViewModel() : this(new KatalogDienst(), new FavoritenDienst())
    {
    }

    public HauptViewModel(KatalogDienst katalogDienst, FavoritenDienst favoritenDienst)
    {
        _katalogDienst = katalogDienst;
        _favoritenDienst = favoritenDienst;

        KopierenBefehl = new AktionsBefehl(_ => SkriptKopieren(), _ => AusgewaehltesSkript is not null);
        SpeichernBefehl = new AktionsBefehl(_ => SkriptSpeichern(), _ => AusgewaehltesSkript is not null);
        SkriptordnerOeffnenBefehl = new AktionsBefehl(_ => SkriptordnerOeffnen());
        SucheLeerenBefehl = new AktionsBefehl(_ => Suchbegriff = string.Empty,
            _ => !string.IsNullOrEmpty(Suchbegriff));
        NeuLadenBefehl = new AktionsBefehl(_ => KatalogLaden());
        FavoritUmschaltenBefehl = new AktionsBefehl(FavoritUmschalten, p => (p ?? AusgewaehltesSkript) is not null);

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
            }
        }
    }

    public bool HatAuswahl => AusgewaehltesSkript is not null;

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
