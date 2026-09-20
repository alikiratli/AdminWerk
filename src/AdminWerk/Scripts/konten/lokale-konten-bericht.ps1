<#
.SYNOPSIS
    Bericht ueber alle lokalen Konten mit Schwerpunkt auf ungenutzten Konten.
.DESCRIPTION
    Listet jedes lokale Konto mit Zustand, letzter Anmeldung, Kennwortalter und
    Gruppenmitgliedschaften. Anschliessend werden die typischen Aufraeumkandidaten
    hervorgehoben: nie angemeldete Konten, lange inaktive Konten, Konten mit nie
    ablaufendem Kennwort und Konten ohne Kennwortpflicht.
.EXAMPLE
    .\lokale-konten-bericht.ps1 -InaktivAbTagen 90
.EXAMPLE
    .\lokale-konten-bericht.ps1 -Computername SRV01, SRV02 -CsvPfad C:\Berichte\konten.csv
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,
    [int]$InaktivAbTagen = 90,
    [string]$CsvPfad
)

$abfrage = {
    param($InaktivAbTagen)

    $stichtag = (Get-Date).AddDays(-$InaktivAbTagen)

    foreach ($konto in Get-LocalUser) {
        $gruppen = @(
            Get-LocalGroup | ForEach-Object {
                $gruppe = $_
                $treffer = Get-LocalGroupMember -Group $gruppe -ErrorAction SilentlyContinue |
                    Where-Object { ($_.Name -split '\\')[-1] -eq $konto.Name }
                if ($treffer) { $gruppe.Name }
            }
        )

        $kennwortAlter = if ($konto.PasswordLastSet) {
            [math]::Round(((Get-Date) - $konto.PasswordLastSet).TotalDays)
        } else { $null }

        $bewertung = 'OK'
        if (-not $konto.Enabled)                { $bewertung = 'deaktiviert' }
        elseif (-not $konto.LastLogon)          { $bewertung = 'nie angemeldet' }
        elseif ($konto.LastLogon -lt $stichtag) { $bewertung = 'inaktiv' }

        [PSCustomObject]@{
            Computer           = $env:COMPUTERNAME
            Konto              = $konto.Name
            Vollname           = $konto.FullName
            Aktiviert          = $konto.Enabled
            LetzteAnmeldung    = $konto.LastLogon
            KennwortGesetzt    = $konto.PasswordLastSet
            KennwortAlterTage  = $kennwortAlter
            KennwortOhneAblauf = ((-not $konto.PasswordExpires) -and $konto.Enabled)
            KennwortNoetig     = $konto.PasswordRequired
            Gruppen            = ($gruppen -join ', ')
            Eingebaut          = ($konto.SID.Value -like '*-500' -or $konto.SID.Value -like '*-501' -or $konto.SID.Value -like '*-503')
            Bewertung          = $bewertung
            Beschreibung       = $konto.Description
        }
    }
}

$konten = foreach ($computer in $Computername) {
    $istLokal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '.')

    try {
        if ($istLokal) {
            & $abfrage $InaktivAbTagen
        }
        else {
            Invoke-Command -ComputerName $computer -ScriptBlock $abfrage -ArgumentList $InaktivAbTagen -ErrorAction Stop |
                Select-Object Computer, Konto, Vollname, Aktiviert, LetzteAnmeldung, KennwortGesetzt,
                    KennwortAlterTage, KennwortOhneAblauf, KennwortNoetig, Gruppen, Eingebaut, Bewertung, Beschreibung
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
}

Write-Host "`n=== Alle lokalen Konten ===`n" -ForegroundColor Cyan
$konten | Sort-Object Computer, Konto |
    Format-Table Computer, Konto, Aktiviert, LetzteAnmeldung, KennwortAlterTage, Bewertung -AutoSize

# --- Aufraeumkandidaten ------------------------------------------------------
Write-Host '=== Aufraeumkandidaten ===' -ForegroundColor Cyan

$nieAngemeldet = $konten | Where-Object { $_.Bewertung -eq 'nie angemeldet' -and -not $_.Eingebaut }
Write-Host "`n--- Aktiviert, aber nie angemeldet ---" -ForegroundColor White
if ($nieAngemeldet) { $nieAngemeldet | Format-Table Computer, Konto, Vollname, Beschreibung -AutoSize }
else { Write-Host 'Keine' -ForegroundColor Green }

$inaktiv = $konten | Where-Object { $_.Bewertung -eq 'inaktiv' -and -not $_.Eingebaut }
Write-Host "--- Keine Anmeldung seit $InaktivAbTagen Tagen ---" -ForegroundColor White
if ($inaktiv) { $inaktiv | Sort-Object LetzteAnmeldung | Format-Table Computer, Konto, LetzteAnmeldung, Gruppen -AutoSize }
else { Write-Host 'Keine' -ForegroundColor Green }

$ohneAblauf = $konten | Where-Object KennwortOhneAblauf
Write-Host '--- Kennwort laeuft nie ab ---' -ForegroundColor White
if ($ohneAblauf) { $ohneAblauf | Format-Table Computer, Konto, KennwortAlterTage, Gruppen -AutoSize }
else { Write-Host 'Keine' -ForegroundColor Green }

$ohneKennwort = $konten | Where-Object { $_.Aktiviert -and -not $_.KennwortNoetig }
Write-Host '--- Kein Kennwort erforderlich ---' -ForegroundColor White
if ($ohneKennwort) {
    $ohneKennwort | Format-Table Computer, Konto, Gruppen -AutoSize
    Write-Warning 'Konten ohne Kennwortpflicht sind ein erhebliches Risiko.'
}
else { Write-Host 'Keine' -ForegroundColor Green }

$altesKennwort = $konten | Where-Object { $_.Aktiviert -and $_.KennwortAlterTage -gt 365 }
Write-Host '--- Kennwort aelter als ein Jahr ---' -ForegroundColor White
if ($altesKennwort) {
    $altesKennwort | Sort-Object KennwortAlterTage -Descending |
        Format-Table Computer, Konto, KennwortAlterTage -AutoSize
}
else { Write-Host 'Keine' -ForegroundColor Green }

Write-Host "`nKonten gesamt: $($konten.Count)" -ForegroundColor White

if ($CsvPfad) {
    $konten | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}
