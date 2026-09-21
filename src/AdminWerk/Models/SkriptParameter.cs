using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AdminWerk.Models;

/// <summary>
/// Ein Parameter aus dem <c>param()</c>-Block eines Skripts, zusammen mit dem Wert,
/// den der Benutzer im Assistenten eingetragen hat.
/// </summary>
public sealed class SkriptParameter : INotifyPropertyChanged
{
    private string _wert = string.Empty;
    private bool _gesetzt;

    public required string Name { get; init; }

    /// <summary>Der Typ, wie er im Skript steht: string, int, string[], switch, ...</summary>
    public string Typ { get; init; } = "string";

    public bool IstSchalter { get; init; }

    /// <summary>Feldtyp (string[], int[]) - mehrere Werte durch Komma getrennt.</summary>
    public bool IstListe { get; init; }

    public bool IstZahl { get; init; }

    public bool IstPflicht { get; init; }

    /// <summary>Standardwert als Quelltext, z. B. <c>15</c> oder <c>@('Spooler', 'BITS')</c>.</summary>
    public string Standardwert { get; init; } = string.Empty;

    /// <summary>Erlaeuterung aus <c>.PARAMETER</c> oder dem Kommentar ueber dem Parameter.</summary>
    public string Beschreibung { get; init; } = string.Empty;

    /// <summary>Werte aus <c>[ValidateSet(...)]</c> - fuellt die Auswahlliste.</summary>
    public IReadOnlyList<string> ErlaubteWerte { get; init; } = [];

    /// <summary>Text aus <c>[ValidateRange(...)]</c>, nur als Hinweis.</summary>
    public string Bereich { get; init; } = string.Empty;

    /// <summary>Eingetragener Wert. Bei Schaltern unbenutzt - dort zaehlt <see cref="Gesetzt"/>.</summary>
    public string Wert
    {
        get => _wert;
        set
        {
            if (_wert == value) return;
            _wert = value;
            Melde();
        }
    }

    /// <summary>Nur fuer Schalter: ob der Schalter in der Aufrufzeile stehen soll.</summary>
    public bool Gesetzt
    {
        get => _gesetzt;
        set
        {
            if (_gesetzt == value) return;
            _gesetzt = value;
            Melde();
        }
    }

    public bool HatAuswahl => ErlaubteWerte.Count > 0;

    /// <summary>Textfeld nur dort, wo weder Schalter noch Auswahlliste passen.</summary>
    public bool HatTextfeld => !IstSchalter && !HatAuswahl;

    public string Anzeigename => IstPflicht ? Name + " *" : Name;

    /// <summary>Zeile unter dem Eingabefeld: Typ, Standardwert, Bereich.</summary>
    public string Hinweis
    {
        get
        {
            var teile = new List<string> { Typ };

            if (!string.IsNullOrEmpty(Bereich))
            {
                teile.Add(Bereich);
            }

            if (!string.IsNullOrEmpty(Standardwert))
            {
                teile.Add("Standard: " + Standardwert);
            }
            else if (IstPflicht)
            {
                teile.Add("erforderlich");
            }

            return string.Join("  ·  ", teile);
        }
    }

    public bool HatBeschreibung => !string.IsNullOrWhiteSpace(Beschreibung);

    /// <summary>Setzt den Parameter auf "nicht angegeben" zurueck.</summary>
    public void Zuruecksetzen()
    {
        Wert = string.Empty;
        Gesetzt = false;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Melde([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
