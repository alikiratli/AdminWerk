using System.Text;
using System.Text.RegularExpressions;
using AdminWerk.Models;

namespace AdminWerk.Services;

/// <summary>
/// Liest den <c>param()</c>-Block eines Skripts aus.
/// </summary>
/// <remarks>
/// Der PowerShell-Parser selbst steht hier nicht zur Verfuegung: er lebt in
/// System.Management.Automation, und das Projekt kommt bewusst ohne Fremdbibliotheken aus.
/// Deshalb ein eigener, kleiner Durchlauf. Er muss nur den Stil beherrschen, in dem der
/// Katalog geschrieben ist - ein vollstaendiger PowerShell-Parser ist er nicht.
/// </remarks>
public static class ParameterDienst
{
    private static readonly Regex PflichtMuster =
        new(@"Mandatory\s*=\s*\$true", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex ParameterHilfeMuster =
        new(@"^\s*\.PARAMETER\s+(?<name>\w+)\s*$", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex PunktAngabeMuster =
        new(@"^\s*\.\w+", RegexOptions.Compiled);

    /// <summary>Liefert die Parameter des Skripts, in der Reihenfolge des Quelltextes.</summary>
    public static IReadOnlyList<SkriptParameter> Auslesen(string quelltext)
    {
        if (string.IsNullOrWhiteSpace(quelltext))
        {
            return [];
        }

        var istCode = CodeMaske(quelltext);
        var block = ParamBlockFinden(quelltext, istCode);
        if (block is null)
        {
            return [];
        }

        var hilfe = HilfeTexte(quelltext);
        var ergebnis = new List<SkriptParameter>();

        foreach (var (start, laenge) in NachKommaTeilen(quelltext, istCode, block.Value.Start, block.Value.Laenge))
        {
            var parameter = EinenParameterLesen(quelltext, istCode, start, laenge, hilfe);
            if (parameter is not null)
            {
                ergebnis.Add(parameter);
            }
        }

        return ergebnis;
    }

    /// <summary>
    /// Markiert, welche Zeichen echter Code sind. Zeichen in Zeichenketten und Kommentaren
    /// zaehlen nicht mit - sonst verzaehlt sich die Klammer- und Kommasuche an einem
    /// Komma im Kommentar oder an einer Klammer in einem Pfad.
    /// </summary>
    private static bool[] CodeMaske(string text)
    {
        var istCode = new bool[text.Length];
        var i = 0;

        while (i < text.Length)
        {
            var c = text[i];

            // Blockkommentar
            if (c == '<' && i + 1 < text.Length && text[i + 1] == '#')
            {
                var ende = text.IndexOf("#>", i + 2, StringComparison.Ordinal);
                i = ende < 0 ? text.Length : ende + 2;
                continue;
            }

            // Zeilenkommentar - ein Doppelkreuz nach einem Backtick ist keiner
            if (c == '#' && (i == 0 || text[i - 1] != '`'))
            {
                while (i < text.Length && text[i] != '\n') i++;
                continue;
            }

            if (c == '\'' || c == '"')
            {
                var anfuehrung = c;
                i++;
                while (i < text.Length)
                {
                    // In doppelten Anfuehrungszeichen maskiert der Backtick
                    if (anfuehrung == '"' && text[i] == '`')
                    {
                        i += 2;
                        continue;
                    }

                    // Verdoppelte Anfuehrungszeichen stehen fuer sich selbst
                    if (text[i] == anfuehrung)
                    {
                        if (i + 1 < text.Length && text[i + 1] == anfuehrung)
                        {
                            i += 2;
                            continue;
                        }

                        i++;
                        break;
                    }

                    i++;
                }

                continue;
            }

            istCode[i] = true;
            i++;
        }

        return istCode;
    }

    /// <summary>Sucht das erste <c>param</c> im Code und liefert den Inhalt seiner Klammer.</summary>
    private static (int Start, int Laenge)? ParamBlockFinden(string text, bool[] istCode)
    {
        for (var i = 0; i + 5 <= text.Length; i++)
        {
            if (!istCode[i]) continue;
            if (char.ToLowerInvariant(text[i]) != 'p') continue;
            if (!text.AsSpan(i, 5).Equals("param", StringComparison.OrdinalIgnoreCase)) continue;

            // Muss ein eigenstaendiges Wort sein, nicht das Ende von "$Suchparam"
            var davor = i > 0 ? text[i - 1] : ' ';
            if (char.IsLetterOrDigit(davor) || davor is '-' or '_' or '$') continue;

            var j = i + 5;
            while (j < text.Length && char.IsWhiteSpace(text[j])) j++;
            if (j >= text.Length || text[j] != '(') continue;

            var ende = KlammerEnde(text, istCode, j);
            if (ende < 0) return null;

            return (j + 1, ende - j - 1);
        }

        return null;
    }

    /// <summary>Position der schliessenden Klammer zur oeffnenden an <paramref name="start"/>.</summary>
    private static int KlammerEnde(string text, bool[] istCode, int start)
    {
        var tiefe = 0;

        for (var i = start; i < text.Length; i++)
        {
            if (!istCode[i]) continue;

            if (text[i] == '(')
            {
                tiefe++;
            }
            else if (text[i] == ')')
            {
                tiefe--;
                if (tiefe == 0) return i;
            }
        }

        return -1;
    }

    /// <summary>Zerlegt den Blockinhalt an den Kommas, die auf oberster Ebene stehen.</summary>
    private static List<(int Start, int Laenge)> NachKommaTeilen(
        string text, bool[] istCode, int start, int laenge)
    {
        var teile = new List<(int, int)>();
        var tiefe = 0;
        var abschnitt = start;
        var ende = start + laenge;

        for (var i = start; i < ende; i++)
        {
            if (!istCode[i]) continue;

            var c = text[i];
            if (c is '(' or '[' or '{')
            {
                tiefe++;
            }
            else if (c is ')' or ']' or '}')
            {
                tiefe--;
            }
            else if (c == ',' && tiefe == 0)
            {
                teile.Add((abschnitt, i - abschnitt));
                abschnitt = i + 1;
            }
        }

        if (ende > abschnitt)
        {
            teile.Add((abschnitt, ende - abschnitt));
        }

        return teile;
    }

    /// <summary>Beschreibungen aus den <c>.PARAMETER</c>-Angaben des Kommentarkopfes.</summary>
    private static Dictionary<string, string> HilfeTexte(string quelltext)
    {
        var texte = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        var anfang = quelltext.IndexOf("<#", StringComparison.Ordinal);
        if (anfang < 0) return texte;

        var ende = quelltext.IndexOf("#>", anfang + 2, StringComparison.Ordinal);
        if (ende < 0) return texte;

        var zeilen = quelltext[(anfang + 2)..ende].Split('\n');
        string? offen = null;
        var gesammelt = new StringBuilder();

        void Ablegen()
        {
            if (offen is not null && gesammelt.Length > 0)
            {
                texte[offen] = gesammelt.ToString();
            }

            gesammelt.Clear();
        }

        foreach (var rohzeile in zeilen)
        {
            var zeile = rohzeile.TrimEnd('\r');
            var treffer = ParameterHilfeMuster.Match(zeile);

            if (treffer.Success)
            {
                Ablegen();
                offen = treffer.Groups["name"].Value;
                continue;
            }

            // Jede andere Punktangabe beendet den Abschnitt
            if (PunktAngabeMuster.IsMatch(zeile))
            {
                Ablegen();
                offen = null;
                continue;
            }

            if (offen is null) continue;

            var text = zeile.Trim();
            if (text.Length == 0) continue;

            if (gesammelt.Length > 0) gesammelt.Append(' ');
            gesammelt.Append(text);
        }

        Ablegen();
        return texte;
    }

    private static SkriptParameter? EinenParameterLesen(
        string text, bool[] istCode, int start, int laenge, Dictionary<string, string> hilfe)
    {
        var roh = text.Substring(start, laenge);

        // Name: das erste Dollarwort, das nicht aus einem Attribut stammt
        var name = string.Empty;
        var namensPos = -1;

        for (var i = start; i < start + laenge; i++)
        {
            if (!istCode[i] || text[i] != '$') continue;

            var j = i + 1;
            while (j < text.Length && (char.IsLetterOrDigit(text[j]) || text[j] == '_')) j++;
            var kandidat = text[(i + 1)..j];

            // true/false stammen aus Attributen wie Mandatory = $true
            if (kandidat.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                kandidat.Equals("false", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            name = kandidat;
            namensPos = i;
            break;
        }

        if (name.Length == 0) return null;

        var vorNamen = text[start..namensPos];
        var nachNamen = text[(namensPos + name.Length + 1)..(start + laenge)];

        var attribute = AttributeLesen(vorNamen);
        var typ = attribute.Typ ?? "object";

        var gleich = nachNamen.IndexOf('=');
        var standard = gleich >= 0 ? nachNamen[(gleich + 1)..].Trim() : string.Empty;

        return new SkriptParameter
        {
            Name = name,
            Typ = typ,
            IstSchalter = typ.Equals("switch", StringComparison.OrdinalIgnoreCase),
            IstListe = typ.EndsWith("[]", StringComparison.Ordinal),
            IstZahl = typ.StartsWith("int", StringComparison.OrdinalIgnoreCase),
            IstPflicht = attribute.Pflicht,
            Standardwert = EinzeiligKuerzen(standard),
            Beschreibung = hilfe.TryGetValue(name, out var aus) ? aus : KommentarUeberDemParameter(roh),
            ErlaubteWerte = attribute.ErlaubteWerte,
            Bereich = attribute.Bereich,
        };
    }

    private static (string? Typ, bool Pflicht, IReadOnlyList<string> ErlaubteWerte, string Bereich)
        AttributeLesen(string vorNamen)
    {
        string? typ = null;
        var pflicht = false;
        IReadOnlyList<string> erlaubt = [];
        var bereich = string.Empty;

        foreach (var inhalt in Attributinhalte(vorNamen))
        {
            if (inhalt.StartsWith("Parameter", StringComparison.OrdinalIgnoreCase))
            {
                if (PflichtMuster.IsMatch(inhalt)) pflicht = true;
                continue;
            }

            if (inhalt.StartsWith("ValidateSet", StringComparison.OrdinalIgnoreCase))
            {
                erlaubt = ZeichenkettenLesen(inhalt);
                continue;
            }

            if (inhalt.StartsWith("ValidateRange", StringComparison.OrdinalIgnoreCase))
            {
                var klammer = Regex.Match(inhalt, @"\((?<w>[^)]*)\)");
                if (klammer.Success)
                {
                    var werte = klammer.Groups["w"].Value.Split(',', StringSplitOptions.TrimEntries);
                    if (werte.Length == 2) bereich = werte[0] + " bis " + werte[1];
                }

                continue;
            }

            // Alles Uebrige ohne Klammer ist die Typangabe
            if (!inhalt.Contains('(') && inhalt.Length > 0)
            {
                typ = inhalt;
            }
        }

        return (typ, pflicht, erlaubt, bereich);
    }

    /// <summary>
    /// Liefert den Inhalt jeder eckigen Klammer auf oberster Ebene. Gezaehlt statt gesucht,
    /// weil Feldtypen verschachtelt sind: aus <c>[string[]]</c> muss <c>string[]</c> werden.
    /// </summary>
    private static List<string> Attributinhalte(string text)
    {
        var inhalte = new List<string>();

        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] != '[') continue;

            var tiefe = 0;
            for (var j = i; j < text.Length; j++)
            {
                if (text[j] == '[')
                {
                    tiefe++;
                }
                else if (text[j] == ']')
                {
                    tiefe--;
                    if (tiefe != 0) continue;

                    inhalte.Add(text[(i + 1)..j].Trim());
                    i = j;
                    break;
                }
            }
        }

        return inhalte;
    }

    private static IReadOnlyList<string> ZeichenkettenLesen(string inhalt)
    {
        var werte = new List<string>();

        foreach (Match m in Regex.Matches(inhalt, "'(?<w>[^']*)'|\"(?<w>[^\"]*)\""))
        {
            werte.Add(m.Groups["w"].Value);
        }

        return werte;
    }

    /// <summary>Der Kommentar ueber dem Parameter dient im Katalog als dessen Erlaeuterung.</summary>
    private static string KommentarUeberDemParameter(string roh)
    {
        var zeilen = new List<string>();

        foreach (var rohzeile in roh.Split('\n'))
        {
            var zeile = rohzeile.Trim();

            if (zeile.StartsWith('#'))
            {
                zeilen.Add(zeile.TrimStart('#').Trim());
            }
            else if (zeile.Length > 0)
            {
                break;
            }
        }

        return string.Join(' ', zeilen);
    }

    private static string EinzeiligKuerzen(string text)
    {
        var einzeilig = Regex.Replace(text, @"\s+", " ").Trim();
        return einzeilig.Length <= 60 ? einzeilig : einzeilig[..57] + "...";
    }

    /// <summary>
    /// Baut die Aufrufzeile aus den eingetragenen Werten. Leere Angaben bleiben weg -
    /// dann gilt der Standardwert des Skripts.
    /// </summary>
    public static string Aufrufzeile(string dateiname, IEnumerable<SkriptParameter> parameter)
    {
        // Voll qualifiziert: in einem WPF-Projekt ist "Path" sonst mehrdeutig
        // (System.Windows.Shapes.Path).
        var zeile = new StringBuilder(".\\" + System.IO.Path.GetFileName(dateiname));

        foreach (var p in parameter)
        {
            if (p.IstSchalter)
            {
                if (p.Gesetzt) zeile.Append(" -").Append(p.Name);
                continue;
            }

            var wert = p.Wert.Trim();
            if (wert.Length == 0) continue;

            zeile.Append(" -").Append(p.Name).Append(' ').Append(WertFormatieren(p, wert));
        }

        return zeile.ToString();
    }

    private static string WertFormatieren(SkriptParameter p, string wert)
    {
        if (!p.IstListe)
        {
            return EinzelwertFormatieren(p, wert);
        }

        // Mehrere Werte trennt der Benutzer durch Komma
        var teile = wert.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return teile.Length == 0
            ? EinzelwertFormatieren(p, wert)
            : string.Join(",", teile.Select(t => EinzelwertFormatieren(p, t)));
    }

    private static string EinzelwertFormatieren(SkriptParameter p, string wert)
    {
        // Zahlen stehen ohne Anfuehrungszeichen, alles andere in einfachen -
        // die schuetzen auch Pfade mit Backslash und Dollarzeichen.
        if (p.IstZahl && long.TryParse(wert, out _))
        {
            return wert;
        }

        return "'" + wert.Replace("'", "''") + "'";
    }
}
