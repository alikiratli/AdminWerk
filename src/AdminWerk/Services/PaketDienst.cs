using System.IO;
using System.IO.Compression;
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
/// Ausgefuehrt wird auch hier nichts. Das Paket ist ein ZIP-Archiv, das man auf das
/// Zielsystem traegt; gestartet wird es dort von Hand.
///
/// Ein Paket ist zugleich die gespeicherte Zusammenstellung: <see cref="Lesen"/> holt
/// Auswahl und Parameterwerte wieder heraus. Einen eigenen Speicher dafuer gibt es
/// nicht - das Archiv, das man ohnehin aufhebt, ist die Vorlage fuer das naechste.
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
    /// <param name="parameterFuer">
    /// Liefert die Parameter eines Skripts samt der Werte, die im Assistenten stehen.
    /// Ohne Angabe bekommt jedes Skript nur seinen sicheren Schalter.
    /// </param>
    /// <returns>Die Anzahl der aufgenommenen Skripte.</returns>
    public int Erzeugen(
        string zielordner,
        string paketName,
        IReadOnlyList<ScriptEintrag> skripte,
        Func<ScriptEintrag, IReadOnlyList<SkriptParameter>>? parameterFuer = null)
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

            var argumente = Argumente(skript, parameterFuer?.Invoke(skript));

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

    /// <summary>
    /// Schreibt das Paket als ZIP-Archiv. Im Archiv liegt ein Ordner, benannt wie die
    /// Datei - entpackt ergibt das dasselbe wie <see cref="Erzeugen"/>.
    /// </summary>
    public int ErzeugenAlsZip(
        string zipPfad,
        string paketName,
        IReadOnlyList<ScriptEintrag> skripte,
        Func<ScriptEintrag, IReadOnlyList<SkriptParameter>>? parameterFuer = null)
    {
        var arbeitsordner = Path.Combine(Path.GetTempPath(), "AdminWerk-" + Guid.NewGuid().ToString("N"));
        var paketOrdner = Path.Combine(arbeitsordner, Path.GetFileNameWithoutExtension(zipPfad));

        try
        {
            var anzahl = Erzeugen(paketOrdner, paketName, skripte, parameterFuer);

            // Erst nach dem erfolgreichen Zusammenstellen: scheitert das, bleibt ein
            // vorhandenes Archiv gleichen Namens unangetastet.
            if (File.Exists(zipPfad))
            {
                File.Delete(zipPfad);
            }

            ZipFile.CreateFromDirectory(
                paketOrdner, zipPfad, CompressionLevel.Optimal, includeBaseDirectory: true);

            return anzahl;
        }
        finally
        {
            try
            {
                Directory.Delete(arbeitsordner, recursive: true);
            }
            catch (IOException)
            {
                // Ein liegengebliebener Temp-Ordner ist kein Grund, das Paket zu verwerfen.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    /// <summary>
    /// Liest ein vorhandenes Paket: ein ZIP-Archiv, einen entpackten Ordner oder dessen
    /// <c>paket.json</c>.
    /// </summary>
    public static GelesenesPaket Lesen(string pfad)
    {
        string json;

        if (Directory.Exists(pfad))
        {
            json = File.ReadAllText(Path.Combine(pfad, "paket.json"), Encoding.UTF8);
        }
        else if (string.Equals(Path.GetExtension(pfad), ".zip", StringComparison.OrdinalIgnoreCase))
        {
            using var archiv = ZipFile.OpenRead(pfad);

            // Die flachste paket.json gewinnt - im Archiv liegt sie eine Ebene tief,
            // hat jemand den Ordnerinhalt selbst gepackt, ganz oben.
            var eintrag = archiv.Entries
                .Where(e => string.Equals(e.Name, "paket.json", StringComparison.OrdinalIgnoreCase))
                .OrderBy(e => e.FullName.Count(z => z is '/' or '\\'))
                .FirstOrDefault()
                ?? throw new InvalidDataException("Das Archiv enthält keine paket.json - ist es ein AdminWerk-Prüfpaket?");

            using var leser = new StreamReader(eintrag.Open(), Encoding.UTF8);
            json = leser.ReadToEnd();
        }
        else
        {
            json = File.ReadAllText(pfad, Encoding.UTF8);
        }

        var paket = JsonSerializer.Deserialize<Paket>(json)
                    ?? throw new InvalidDataException("paket.json ist leer.");

        return new GelesenesPaket(
            paket.Name,
            paket.Skripte
                .Where(s => !string.IsNullOrWhiteSpace(s.Id))
                .Select(s => new GelesenesSkript(s.Id, s.Titel, LesbareArgumente(s.Argumente)))
                .ToList());
    }

    /// <summary>
    /// Bringt die Argumente aus der JSON-Form in die Form des Assistenten: Schalter als
    /// <c>true</c>, alles andere als Text, Listen durch Komma getrennt.
    /// </summary>
    private static Dictionary<string, object> LesbareArgumente(Dictionary<string, object> roh)
    {
        var ergebnis = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

        foreach (var (name, wert) in roh)
        {
            if (wert is not JsonElement element)
            {
                continue;
            }

            switch (element.ValueKind)
            {
                case JsonValueKind.True:
                    ergebnis[name] = true;
                    break;
                case JsonValueKind.String:
                    ergebnis[name] = element.GetString() ?? string.Empty;
                    break;
                case JsonValueKind.Number:
                    ergebnis[name] = element.GetRawText();
                    break;
                case JsonValueKind.Array:
                    ergebnis[name] = string.Join(", ", element.EnumerateArray()
                        .Select(e => e.ValueKind == JsonValueKind.String ? e.GetString() : e.GetRawText()));
                    break;
            }
        }

        return ergebnis;
    }

    /// <summary>
    /// Baut die Aufrufargumente eines Skripts: die Eingaben aus dem Assistenten,
    /// darueber der sichere Schalter aus dem Katalog.
    /// </summary>
    /// <remarks>
    /// Als Name-Wert-Paare, nicht als Zeichenkette: PowerShell verteilt ein
    /// gesplattetes Feld der Reihe nach auf die Stellungsparameter, "-NurPruefen"
    /// waere dann ein Dienstname und kein Schalter.
    ///
    /// Bei veraendernden Skripten bleiben gesetzte Schalter aussen vor. Ein Paket ist
    /// ein Pruefpaket; wer "-Anwenden" im Assistenten setzt, meint den Einzelaufruf in
    /// der PowerShell, nicht einen Auditlauf ueber mehrere Systeme.
    /// </remarks>
    private static Dictionary<string, object> Argumente(
        ScriptEintrag skript, IReadOnlyList<SkriptParameter>? parameter)
    {
        var argumente = new Dictionary<string, object>();

        foreach (var p in parameter ?? [])
        {
            if (p.IstSchalter)
            {
                if (p.Gesetzt && !skript.Veraendert)
                {
                    argumente[p.Name] = true;
                }

                continue;
            }

            var wert = p.Wert.Trim();
            if (wert.Length == 0)
            {
                continue;
            }

            argumente[p.Name] = WertFuerJson(p, wert);
        }

        // Zuletzt, damit er nicht zu ueberschreiben ist.
        if (!string.IsNullOrWhiteSpace(skript.SichererSchalter))
        {
            argumente[skript.SichererSchalter.Trim().TrimStart('-')] = true;
        }

        return argumente;
    }

    private static object WertFuerJson(SkriptParameter p, string wert)
    {
        if (!p.IstListe)
        {
            return p.IstZahl && long.TryParse(wert, out var zahl) ? zahl : wert;
        }

        // Mehrere Werte trennt der Benutzer durch Komma - dasselbe wie im Assistenten.
        var teile = wert.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (teile.Length == 0)
        {
            return wert;
        }

        if (!p.IstZahl)
        {
            return teile;
        }

        var zahlen = new List<object>();
        foreach (var teil in teile)
        {
            zahlen.Add(long.TryParse(teil, out var z) ? z : teil);
        }

        return zahlen.ToArray();
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
        text.AppendLine("Kam das Archiv per Download oder E-Mail, markiert Windows die entpackten");
        text.AppendLine("Dateien als „aus dem Internet“, und die Ausführungsrichtlinie `RemoteSigned`");
        text.AppendLine("verweigert sie. Nach dem Lesen der Skripte im Paketordner:");
        text.AppendLine();
        text.AppendLine("```powershell");
        text.AppendLine("Get-ChildItem -Recurse | Unblock-File");
        text.AppendLine("```");
        text.AppendLine();
        text.AppendLine("## Mehrere Computer");
        text.AppendLine();
        text.AppendLine("Das Paket auf jedem Computer starten und die Berichte in einem Ordner");
        text.AppendLine("sammeln. Daraus wird ein Gesamtbericht mit einer Übersicht Prüfung mal");
        text.AppendLine("Computer:");
        text.AppendLine();
        text.AppendLine("```powershell");
        text.AppendLine(".\\Start-Pruefung.ps1 -Zusammenfuehren C:\\Berichte -Oeffnen");
        text.AppendLine("```");
        text.AppendLine();
        text.AppendLine("Dabei wird nichts geprüft, nur gelesen. Gibt es von einem Computer mehrere");
        text.AppendLine("Läufe, gilt der neueste; auch ein früherer Gesamtbericht darf im Ordner liegen.");
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

    /// <summary>Was aus einem vorhandenen Paket zurueckkommt.</summary>
    public sealed record GelesenesPaket(string Name, IReadOnlyList<GelesenesSkript> Skripte);

    /// <param name="Argumente">
    /// Parametername auf <c>true</c> (Schalter) oder den Text, wie er im Assistenten steht.
    /// </param>
    public sealed record GelesenesSkript(string Id, string Titel, IReadOnlyDictionary<string, object> Argumente);

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
