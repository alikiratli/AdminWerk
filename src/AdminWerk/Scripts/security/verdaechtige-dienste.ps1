<#
.SYNOPSIS
    Sucht nach Diensten mit auffaelligen Merkmalen.
.DESCRIPTION
    Prueft alle Windows-Dienste auf typische Persistenz- und Angriffsmuster:
    ausfuehrbare Dateien ausserhalb der Systemverzeichnisse, nicht in
    Anfuehrungszeichen gesetzte Pfade mit Leerzeichen (Unquoted Service Path)
    sowie fehlende oder ungueltige digitale Signaturen.
.NOTES
    Benoetigt Administratorrechte fuer vollstaendige Ergebnisse.
.EXAMPLE
    .\verdaechtige-dienste.ps1
#>
[CmdletBinding()]
param()

$dienste = Get-CimInstance -ClassName Win32_Service

$bericht = foreach ($dienst in $dienste) {
    $pfadAngabe = [string]$dienst.PathName
    if (-not $pfadAngabe) { continue }

    # Ausfuehrbare Datei aus der Befehlszeile herausloesen
    $programm = if ($pfadAngabe -match '^"([^"]+)"') { $matches[1] }
                elseif ($pfadAngabe -match '^([^\s]+\.exe)') { $matches[1] }
                else { ($pfadAngabe -split ' ')[0] }

    $ungequotet = ($pfadAngabe -notmatch '^"') -and ($pfadAngabe -match '\s') -and ($programm -match '\s')
    $ausserhalb = $programm -notmatch '^[A-Za-z]:\(Windows|Program Files|Program Files \(x86\))\'

    $signatur = 'nicht geprueft'
    if (Test-Path -Path $programm -ErrorAction SilentlyContinue) {
        $pruefung = Get-AuthenticodeSignature -FilePath $programm -ErrorAction SilentlyContinue
        if ($pruefung) { $signatur = $pruefung.Status }
    }
    else {
        $signatur = 'Datei nicht gefunden'
    }

    $auffaellig = $ungequotet -or $ausserhalb -or ($signatur -notin 'Valid', 'nicht geprueft')
    if (-not $auffaellig) { continue }

    $gruende = @()
    if ($ungequotet) { $gruende += 'Pfad ohne Anfuehrungszeichen' }
    if ($ausserhalb) { $gruende += 'ausserhalb der Systemverzeichnisse' }
    if ($signatur -notin 'Valid', 'nicht geprueft') { $gruende += "Signatur: $signatur" }

    [PSCustomObject]@{
        Dienst      = $dienst.Name
        Anzeigename = $dienst.DisplayName
        Status      = $dienst.State
        Starttyp    = $dienst.StartMode
        Konto       = $dienst.StartName
        Programm    = $programm
        Befund      = $gruende -join '; '
    }
}

Write-Host "`n=== Auffaellige Dienste: $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

if (-not $bericht) {
    Write-Host 'Keine Auffaelligkeiten gefunden.' -ForegroundColor Green
    return
}

$bericht | Sort-Object Dienst | Format-List

Write-Host "Auffaellige Dienste: $($bericht.Count) von $($dienste.Count)" -ForegroundColor Yellow

$ungequotete = $bericht | Where-Object Befund -match 'Anfuehrungszeichen'
if ($ungequotete) {
    Write-Warning "$($ungequotete.Count) Dienste mit ungequotetem Pfad - Moeglichkeit zur Rechteausweitung."
}
