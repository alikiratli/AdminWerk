using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace AdminWerk.Views;

/// <summary>
/// Angehaengte Eigenschaft, die PowerShell-Quelltext eingefaerbt in eine
/// <see cref="RichTextBox"/> schreibt. Bewusst eine leichtgewichtige Regex-Loesung:
/// sie muss lesbar einfaerben, keinen vollstaendigen Parser ersetzen.
/// </summary>
public static class PowerShellHervorhebung
{
    private static readonly Regex Tokenerkennung = new(
        """
        (?<kommentar><\#[\s\S]*?\#>|\#[^\r\n]*)
        |(?<zeichenkette>"(?:[^"`]|`.)*"|'[^']*')
        |(?<variable>\$(?:\{[^}]*\}|[A-Za-z_][\w:]*))
        |(?<schluesselwort>(?i:\b(?:if|else|elseif|foreach|for|while|do|switch|function|filter|param|return|break|continue|try|catch|finally|throw|begin|process|end|in|not|and|or)\b))
        |(?<cmdlet>\b[A-Z][A-Za-z]*-[A-Z][A-Za-z]*\b)
        |(?<parameter>(?<=[\s\(])-[A-Za-z][A-Za-z0-9]*\b)
        |(?<zahl>\b\d+(?:\.\d+)?\b)
        """,
        RegexOptions.Compiled | RegexOptions.IgnorePatternWhitespace | RegexOptions.CultureInvariant);

    public static readonly DependencyProperty QuelltextProperty = DependencyProperty.RegisterAttached(
        "Quelltext",
        typeof(string),
        typeof(PowerShellHervorhebung),
        new PropertyMetadata(string.Empty, BeiQuelltextAenderung));

    public static void SetQuelltext(DependencyObject element, string wert)
        => element.SetValue(QuelltextProperty, wert);

    public static string GetQuelltext(DependencyObject element)
        => (string)element.GetValue(QuelltextProperty);

    private static void BeiQuelltextAenderung(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not RichTextBox feld)
        {
            return;
        }

        var quelltext = e.NewValue as string ?? string.Empty;
        var absatz = new Paragraph { Margin = new Thickness(0) };

        foreach (var lauf in Zerlegen(quelltext))
        {
            absatz.Inlines.Add(lauf);
        }

        feld.Document = new FlowDocument(absatz)
        {
            PageWidth = 2400,   // verhindert Zeilenumbruch; stattdessen waagerechter Bildlauf
            PagePadding = new Thickness(0)
        };
        feld.ScrollToHome();
    }

    private static IEnumerable<Run> Zerlegen(string quelltext)
    {
        var position = 0;

        foreach (Match treffer in Tokenerkennung.Matches(quelltext))
        {
            if (treffer.Index > position)
            {
                yield return Einfaerben(quelltext[position..treffer.Index], "Syntax.Standard");
            }

            yield return Einfaerben(treffer.Value, PinselSchluessel(treffer));
            position = treffer.Index + treffer.Length;
        }

        if (position < quelltext.Length)
        {
            yield return Einfaerben(quelltext[position..], "Syntax.Standard");
        }
    }

    private static string PinselSchluessel(Match treffer)
    {
        foreach (var name in new[] { "kommentar", "zeichenkette", "variable", "schluesselwort", "cmdlet", "parameter", "zahl" })
        {
            if (treffer.Groups[name].Success)
            {
                return name switch
                {
                    "kommentar" => "Syntax.Kommentar",
                    "zeichenkette" => "Syntax.Zeichenkette",
                    "variable" => "Syntax.Variable",
                    "schluesselwort" => "Syntax.Schluesselwort",
                    "cmdlet" => "Syntax.Cmdlet",
                    "parameter" => "Syntax.Parameter",
                    _ => "Syntax.Zahl"
                };
            }
        }

        return "Syntax.Standard";
    }

    private static Run Einfaerben(string text, string pinselSchluessel)
    {
        var lauf = new Run(text);

        if (Application.Current?.TryFindResource(pinselSchluessel) is Brush pinsel)
        {
            lauf.Foreground = pinsel;
        }

        return lauf;
    }
}
