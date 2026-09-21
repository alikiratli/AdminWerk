using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AdminWerk.Models;

/// <summary>Ein einzelnes PowerShell-Skript samt Metadaten aus dem Katalog.</summary>
public sealed class ScriptEintrag : INotifyPropertyChanged
{
    private bool _istFavorit;
    private bool _imPaket;

    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("kategorie")]
    public string KategorieId { get; init; } = string.Empty;

    [JsonPropertyName("titel")]
    public string Titel { get; init; } = string.Empty;

    [JsonPropertyName("beschreibung")]
    public string Beschreibung { get; init; } = string.Empty;

    /// <summary>Pfad der .ps1-Datei relativ zum Skriptverzeichnis.</summary>
    [JsonPropertyName("datei")]
    public string Datei { get; init; } = string.Empty;

    [JsonPropertyName("tags")]
    public string[] Tags { get; init; } = [];

    /// <summary>True, wenn das Skript eine erhoehte PowerShell-Sitzung benoetigt.</summary>
    [JsonPropertyName("adminRechte")]
    public bool AdminRechte { get; init; }

    /// <summary>True, wenn das Skript am System etwas aendern kann.</summary>
    [JsonPropertyName("veraendert")]
    public bool Veraendert { get; init; }

    /// <summary>
    /// Was ein Pruefpaket ergaenzen muss, damit der Lauf nichts veraendert - etwa
    /// <c>-NurPruefen</c>. Leer bedeutet: das Skript ist von sich aus ein Testlauf und
    /// braucht erst <c>-Anwenden</c>, um wirklich zu handeln.
    /// </summary>
    [JsonPropertyName("sichererSchalter")]
    public string SichererSchalter { get; init; } = string.Empty;

    /// <summary>Freitext zu Zielsystemen bzw. benoetigten Modulen.</summary>
    [JsonPropertyName("voraussetzung")]
    public string Voraussetzung { get; init; } = string.Empty;

    /// <summary>Anzeigename der Kategorie. Wird beim Laden des Katalogs nachgetragen.</summary>
    [JsonIgnore]
    public string KategorieName { get; set; } = string.Empty;

    /// <summary>Skriptinhalt. Wird beim Laden des Katalogs aus <see cref="Datei"/> gefuellt.</summary>
    [JsonIgnore]
    public string Inhalt { get; set; } = string.Empty;

    [JsonIgnore]
    public string TagZeile => string.Join("  ·  ", Tags);

    [JsonIgnore]
    public string RechteText => AdminRechte ? "Administratorrechte erforderlich" : "Standardbenutzer genügt";

    /// <summary>
    /// Vom Benutzer als Favorit markiert. Wird nicht im Katalog gespeichert, sondern
    /// je Benutzer im Anwendungsdatenverzeichnis abgelegt.
    /// </summary>
    [JsonIgnore]
    public bool IstFavorit
    {
        get => _istFavorit;
        set
        {
            if (_istFavorit == value)
            {
                return;
            }

            _istFavorit = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IstFavorit)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(FavoritText)));
        }
    }

    /// <summary>Beschriftung der Favoritenschaltflaeche im Detailbereich.</summary>
    [JsonIgnore]
    public string FavoritText => IstFavorit ? "★  Favorit" : "☆  Als Favorit merken";

    /// <summary>
    /// Fuer das naechste Pruefpaket ausgewaehlt. Anders als die Favoriten eine
    /// Zusammenstellung fuer den Augenblick - sie wird nicht gespeichert.
    /// </summary>
    [JsonIgnore]
    public bool ImPaket
    {
        get => _imPaket;
        set
        {
            if (_imPaket == value)
            {
                return;
            }

            _imPaket = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ImPaket)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Alle durchsuchbaren Felder in einem vorbereiteten Kleinbuchstaben-Puffer.</summary>
    [JsonIgnore]
    public string Suchtext { get; private set; } = string.Empty;

    public void SuchindexAufbauen() =>
        Suchtext = $"{Titel} {Beschreibung} {string.Join(' ', Tags)} {Inhalt}".ToLowerInvariant();
}
