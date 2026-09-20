using System.IO;
using System.Text.Json;

namespace AdminWerk.Services;

/// <summary>
/// Speichert die Favoritenauswahl je Benutzer unter
/// <c>%AppData%\AdminWerk\favoriten.json</c>.
/// Bewusst getrennt vom Skriptkatalog: der Katalog gehoert zur Anwendung,
/// die Favoriten gehoeren dem Benutzer.
/// </summary>
public sealed class FavoritenDienst
{
    private static readonly JsonSerializerOptions JsonOptionen = new() { WriteIndented = true };

    public string Dateipfad { get; }

    public FavoritenDienst(string? dateipfad = null)
    {
        Dateipfad = dateipfad ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "AdminWerk",
            "favoriten.json");
    }

    /// <summary>
    /// Liest die gespeicherten Skript-IDs. Fehlt die Datei oder ist sie beschaedigt,
    /// wird eine leere Auswahl geliefert - ein unlesbarer Favoritenspeicher darf die
    /// Anwendung nicht am Starten hindern.
    /// </summary>
    public HashSet<string> Laden()
    {
        try
        {
            if (!File.Exists(Dateipfad))
            {
                return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            }

            var ids = JsonSerializer.Deserialize<string[]>(File.ReadAllText(Dateipfad));
            return new HashSet<string>(ids ?? [], StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        }
    }

    /// <summary>Schreibt die Auswahl zurueck. Gibt bei Erfolg <c>null</c> zurueck, sonst die Fehlermeldung.</summary>
    public string? Speichern(IEnumerable<string> skriptIds)
    {
        try
        {
            var verzeichnis = Path.GetDirectoryName(Dateipfad);
            if (!string.IsNullOrEmpty(verzeichnis) && !Directory.Exists(verzeichnis))
            {
                Directory.CreateDirectory(verzeichnis);
            }

            var sortiert = skriptIds.OrderBy(id => id, StringComparer.Ordinal).ToArray();
            File.WriteAllText(Dateipfad, JsonSerializer.Serialize(sortiert, JsonOptionen));
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }
}
