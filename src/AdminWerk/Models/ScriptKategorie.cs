using System.Text.Json.Serialization;

namespace AdminWerk.Models;

/// <summary>Oberkategorie des Skriptkatalogs, z. B. "System" oder "Netzwerk".</summary>
public sealed class ScriptKategorie
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("beschreibung")]
    public string Beschreibung { get; init; } = string.Empty;

    /// <summary>Kurzes Symbol (Unicode) fuer die Navigationsleiste.</summary>
    [JsonPropertyName("symbol")]
    public string Symbol { get; init; } = string.Empty;
}
