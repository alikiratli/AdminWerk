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

    private readonly KatalogDienst _katalogDienst;
    private readonly List<ScriptEintrag> _alleSkripte = [];

    private ScriptKategorie? _ausgewaehlteKategorie;
    private ScriptEintrag? _ausgewaehltesSkript;
    private string _suchbegriff = string.Empty;
    private string _statusmeldung = string.Empty;
    private string? _ladefehler;

    public HauptViewModel() : this(new KatalogDienst())
    {
    }

    public HauptViewModel(KatalogDienst katalogDienst)
    {
        _katalogDienst = katalogDienst;

        KopierenBefehl = new AktionsBefehl(_ => SkriptKopieren(), _ => AusgewaehltesSkript is not null);
        SpeichernBefehl = new AktionsBefehl(_ => SkriptSpeichern(), _ => AusgewaehltesSkript is not null);
        SkriptordnerOeffnenBefehl = new AktionsBefehl(_ => SkriptordnerOeffnen());
        SucheLeerenBefehl = new AktionsBefehl(_ => Suchbegriff = string.Empty,
            _ => !string.IsNullOrEmpty(Suchbegriff));
        NeuLadenBefehl = new AktionsBefehl(_ => KatalogLaden());

        KatalogLaden();
    }

    public ObservableCollection<ScriptKategorie> Kategorien { get; } = [];

    public ObservableCollection<ScriptEintrag> GefilterteSkripte { get; } = [];

    public AktionsBefehl KopierenBefehl { get; }

    public AktionsBefehl SpeichernBefehl { get; }

    public AktionsBefehl SkriptordnerOeffnenBefehl { get; }

    public AktionsBefehl SucheLeerenBefehl { get; }

    public AktionsBefehl NeuLadenBefehl { get; }

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

    public string KatalogInfo => $"{_alleSkripte.Count} Skripte in {Math.Max(Kategorien.Count - 1, 0)} Kategorien";

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
            .Where(s => kategorieId == AlleKategorienId || s.KategorieId == kategorieId)
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
