using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using AdminWerk.Models;

namespace AdminWerk.Services;

/// <summary>
/// Stellt aus ausgewaehlten Skripten ein Pruefpaket zusammen: die .ps1-Dateien, eine
/// Beschreibung des Pakets und den Laeufer, der daraus einen HTML-Bericht macht.
/// </summary>
/// <remarks>
/// Ausgefuehrt wird auch hier nichts. Das Paket ist ein Ordner, den man auf das
/// Zielsystem traegt; gestartet wird es dort von Hand.
/// </remarks>
public sealed class PaketDienst
{
    private static readonly JsonSerializerOptions JsonOptionen = new()
    {
        WriteIndented = true,
        // Umlaute in Titeln sollen im paket.json lesbar bleiben, nicht als \uXXXX.
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly string _skriptVerzeichnis;
    private readonly string _vorlagenVerzeichnis;

    public PaketDienst(string skriptVerzeichnis, string? vorlagenVerzeichnis = null)
    {
        _skriptVerzeichnis = skriptVerzeichnis;
        _vorlagenVerzeichnis = vorlagenVerzeichnis
                               ?? Path.Combine(AppContext.BaseDirectory, "Vorlagen");
    }

    /// <summary>Schreibt das Paket nach <paramref name="zielordner"/>.</summary>
    /// <returns>Die Anzahl der aufgenommenen Skripte.</returns>
    public int Erzeugen(string zielordner, string paketName, IReadOnlyList<ScriptEintrag> skripte)
    {
        if (skripte.Count == 0)
        {
            throw new InvalidOperationException("Das Paket enthält kein Skript.");
        }

        var vorlage = Path.Combine(_vorlagenVerzeichnis, "Start-Pruefung.ps1");
        if (!File.Exists(vorlage))
        {
            throw new FileNotFoundException(
                $"Die Vorlage für den Paketläufer fehlt: {vorlage}", vorlage);
        }

        Directory.CreateDirectory(zielordner);

        var eintraege = new List<PaketEintrag>();

        foreach (var skript in skripte)
        {
            var quelle = Path.Combine(
                _skriptVerzeichnis, skript.Datei.Replace('/', Path.DirectorySeparatorChar));

            if (!File.Exists(quelle))
            {
                continue;
            }

            var ziel = Path.Combine(
                zielordner, skript.Datei.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(ziel)!);
            File.Copy(quelle, ziel, overwrite: true);

            // Der sichere Schalter kommt aus dem Katalog und ist dort gegen den
            // Quelltext geprueft. Ohne ihn wuerde ein Auditlauf Dienste starten.
            //
            // Als Name-Wert-Paar, nicht als Zeichenkette: PowerShell verteilt ein
            // gesplattetes Feld auf die Parameter der Reihe nach. "-NurPruefen" waere
            // dann der erste Stellungsparameter und nicht der Schalter.
            var argumente = new Dictionary<string, object>();
            if (!string.IsNullOrWhiteSpace(skript.SichererSchalter))
            {
                argumente[skript.SichererSchalter.Trim().TrimStart('-')] = true;
            }

            eintraege.Add(new PaketEintrag
            {
                Id = skript.Id,
                Titel = skript.Titel,
                Beschreibung = skript.Beschreibung,
                Datei = skript.Datei,
                AdminRechte = skript.AdminRechte,
                Veraendert = skript.Veraendert,
                Argumente = argumente
            });
        }

        var paket = new Paket
        {
            Name = paketName,
            Erzeugt = DateTime.Now,
            Skripte = eintraege
        };

        // UTF-8 ohne BOM: der Laeufer liest die Datei mit -Encoding UTF8.
        var ohneStueckliste = new UTF8Encoding(false);
        File.WriteAllText(
            Path.Combine(zielordner, "paket.json"),
            JsonSerializer.Serialize(paket, JsonOptionen),
            ohneStueckliste);

        File.Copy(vorlage, Path.Combine(zielordner, "Start-Pruefung.ps1"), overwrite: true);

        File.WriteAllText(
            Path.Combine(zielordner, "LIESMICH.md"),
            Liesmich(paket),
            ohneStueckliste);

        return eintraege.Count;
    }

    private static string Liesmich(Paket paket)
    {
        var text = new StringBuilder();

        text.AppendLine($"# {paket.Name}");
        text.AppendLine();
        text.AppendLine($"Zusammengestellt mit AdminWerk am {paket.Erzeugt:dd.MM.yyyy HH:mm}.");
        text.AppendLine();
        text.AppendLine("## Ausführen");
        text.AppendLine();
        text.AppendLine("```powershell");
        text.AppendLine(".\\Start-Pruefung.ps1 -Oeffnen");
        text.AppendLine("```");
        text.AppendLine();
        text.AppendLine("Der Läufer ruft jedes Skript einmal auf, fängt dessen Ausgabe ein und");
        text.AppendLine("schreibt daraus einen HTML-Bericht. Fällt ein Skript um, laufen die");
        text.AppendLine("übrigen weiter.");
        text.AppendLine();

        var brauchtAdmin = paket.Skripte.Count(s => s.AdminRechte);
        if (brauchtAdmin > 0)
        {
            text.AppendLine($"**{brauchtAdmin} der {paket.Skripte.Count} Skripte brauchen Administratorrechte.**");
            text.AppendLine("Ohne erhöhte Sitzung liefern sie nur Teilergebnisse.");
            text.AppendLine();
        }

        text.AppendLine("## Was dieses Paket nicht tut");
        text.AppendLine();
        text.AppendLine("Es verändert nichts. Skripte, die das könnten, werden mit dem Schalter");
        text.AppendLine("aufgerufen, der sie auf einen reinen Prüflauf beschränkt.");
        text.AppendLine();
        text.AppendLine("## Enthaltene Prüfungen");
        text.AppendLine();

        foreach (var s in paket.Skripte)
        {
            var kennzeichen = s.AdminRechte ? " *(Administratorrechte)*" : string.Empty;
            text.AppendLine($"* **{s.Titel}**{kennzeichen}  ");
            text.AppendLine($"  `{s.Datei}` — {s.Beschreibung}");
        }

        return text.ToString();
    }

    private sealed class Paket
    {
        [JsonPropertyName("name")]
        public string Name { get; init; } = string.Empty;

        [JsonPropertyName("erzeugt")]
        public DateTime Erzeugt { get; init; }

        [JsonPropertyName("skripte")]
        public List<PaketEintrag> Skripte { get; init; } = [];
    }

    private sealed class PaketEintrag
    {
        [JsonPropertyName("id")]
        public string Id { get; init; } = string.Empty;

        [JsonPropertyName("titel")]
        public string Titel { get; init; } = string.Empty;

        [JsonPropertyName("beschreibung")]
        public string Beschreibung { get; init; } = string.Empty;

        [JsonPropertyName("datei")]
        public string Datei { get; init; } = string.Empty;

        [JsonPropertyName("adminRechte")]
        public bool AdminRechte { get; init; }

        [JsonPropertyName("veraendert")]
        public bool Veraendert { get; init; }

        /// <summary>Parametername ohne Bindestrich auf seinen Wert - der Laeufer splattet das.</summary>
        [JsonPropertyName("argumente")]
        public Dictionary<string, object> Argumente { get; init; } = [];
    }
}
