using System.IO;
using System.Text.Json;
using AdminWerk.Models;

namespace AdminWerk.Services;

/// <summary>
/// Laedt den Skriptkatalog (<c>Scripts/catalog.json</c>) und die zugehoerigen .ps1-Dateien
/// aus dem Programmverzeichnis. Admins koennen dort eigene Skripte ergaenzen.
/// </summary>
public sealed class KatalogDienst
{
    private static readonly JsonSerializerOptions JsonOptionen = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };

    public string SkriptVerzeichnis { get; }

    public KatalogDienst(string? skriptVerzeichnis = null)
        => SkriptVerzeichnis = skriptVerzeichnis ?? Path.Combine(AppContext.BaseDirectory, "Scripts");

    /// <summary>Vollstaendiger Pfad der .ps1-Datei eines Katalogeintrags.</summary>
    public string SkriptPfad(ScriptEintrag skript)
        => Path.Combine(SkriptVerzeichnis, skript.Datei.Replace('/', Path.DirectorySeparatorChar));

    /// <summary>
    /// Liest den Katalog ein. Fehlt eine .ps1-Datei, bleibt der Eintrag erhalten und traegt
    /// stattdessen einen Hinweistext – die Anwendung soll wegen eines Skripts nicht scheitern.
    /// </summary>
    public ScriptKatalog Laden()
    {
        var katalogPfad = Path.Combine(SkriptVerzeichnis, "catalog.json");
        if (!File.Exists(katalogPfad))
        {
            throw new FileNotFoundException(
                $"Der Skriptkatalog wurde nicht gefunden: {katalogPfad}", katalogPfad);
        }

        var json = File.ReadAllText(katalogPfad);
        var katalog = JsonSerializer.Deserialize<ScriptKatalog>(json, JsonOptionen)
                      ?? throw new InvalidDataException($"Der Skriptkatalog ist leer oder ungültig: {katalogPfad}");

        foreach (var skript in katalog.Skripte)
        {
            skript.Inhalt = SkriptInhaltLesen(skript);
            skript.SuchindexAufbauen();
        }

        return katalog;
    }

    private string SkriptInhaltLesen(ScriptEintrag skript)
    {
        if (string.IsNullOrWhiteSpace(skript.Datei))
        {
            return "# Für diesen Eintrag ist keine Skriptdatei hinterlegt.";
        }

        var pfad = SkriptPfad(skript);
        return File.Exists(pfad)
            ? File.ReadAllText(pfad)
            : $"# Skriptdatei nicht gefunden: {pfad}";
    }
}
