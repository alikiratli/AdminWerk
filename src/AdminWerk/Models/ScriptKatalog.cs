using System.Text.Json.Serialization;

namespace AdminWerk.Models;

/// <summary>Wurzelobjekt der Datei <c>catalog.json</c>.</summary>
public sealed class ScriptKatalog
{
    [JsonPropertyName("kategorien")]
    public List<ScriptKategorie> Kategorien { get; init; } = [];

    [JsonPropertyName("skripte")]
    public List<ScriptEintrag> Skripte { get; init; } = [];
}
