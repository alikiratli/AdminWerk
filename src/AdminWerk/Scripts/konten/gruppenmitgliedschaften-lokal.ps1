<#
.SYNOPSIS
    Berichtet alle lokalen Gruppen und ihre Mitglieder.
.DESCRIPTION
    Zwei Blickrichtungen auf dieselben Daten: einmal je Gruppe (wer ist drin)
    und einmal je Konto (wo ist es ueberall Mitglied). Die zweite Sicht ist bei
    Berechtigungsfragen meist die hilfreichere.
    Funktioniert auch ueber mehrere Computer hinweg.
.EXAMPLE
    .\gruppenmitgliedschaften-lokal.ps1
.EXAMPLE
    .\gruppenmitgliedschaften-lokal.ps1 -Computername SRV01, SRV02 -CsvPfad C:\Berichte\gruppen.csv
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME,

    # Leere Gruppen ausblenden - davon bringt Windows viele mit.
    [switch]$LeereAusblenden = $true,

    [string]$CsvPfad
)

$abfrage = {
    foreach ($gruppe in Get-LocalGroup) {
        $mitglieder = Get-LocalGroupMember -Group $gruppe -ErrorAction SilentlyContinue

        if (-not $mitglieder) {
            [PSCustomObject]@{
                Computer     = $env:COMPUTERNAME
                Gruppe       = $gruppe.Name
                Beschreibung = $gruppe.Description
                Mitglied     = '(leer)'
                Typ          = '-'
                Herkunft     = '-'
            }
            continue
        }

        foreach ($mitglied in $mitglieder) {
            [PSCustomObject]@{
                Computer     = $env:COMPUTERNAME
                Gruppe       = $gruppe.Name
                Beschreibung = $gruppe.Description
                Mitglied     = $mitglied.Name
                Typ          = $mitglied.ObjectClass
                Herkunft     = $mitglied.PrincipalSource
            }
        }
    }
}

$daten = foreach ($computer in $Computername) {
    $istLokal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '.')

    try {
        if ($istLokal) {
            & $abfrage
        }
        else {
            Invoke-Command -ComputerName $computer -ScriptBlock $abfrage -ErrorAction Stop |
                Select-Object Computer, Gruppe, Beschreibung, Mitglied, Typ, Herkunft
        }
    }
    catch {
        Write-Warning "$computer : $($_.Exception.Message)"
    }
}

$anzeige = if ($LeereAusblenden) { $daten | Where-Object Mitglied -ne '(leer)' } else { $daten }

# --- Sicht 1: je Gruppe ------------------------------------------------------
Write-Host "`n=== Gruppen und ihre Mitglieder ===`n" -ForegroundColor Cyan

foreach ($gruppe in $anzeige | Group-Object Computer, Gruppe) {
    $erstes = $gruppe.Group | Select-Object -First 1

    Write-Host ('{0}\{1}  ({2} Mitglieder)' -f $erstes.Computer, $erstes.Gruppe, $gruppe.Count) -ForegroundColor White
    if ($erstes.Beschreibung) {
        Write-Host "  $($erstes.Beschreibung)" -ForegroundColor DarkGray
    }

    foreach ($mitglied in $gruppe.Group) {
        Write-Host ('    {0,-50} {1} / {2}' -f $mitglied.Mitglied, $mitglied.Typ, $mitglied.Herkunft)
    }

    Write-Host ''
}

# --- Sicht 2: je Konto -------------------------------------------------------
Write-Host '=== Mitgliedschaften je Konto ===' -ForegroundColor Cyan

$anzeige | Group-Object Mitglied | Sort-Object Count -Descending |
    Select-Object @{ Name = 'Konto'; Expression = { $_.Name } },
        @{ Name = 'Anzahl'; Expression = { $_.Count } },
        @{ Name = 'Gruppen'; Expression = { ($_.Group | ForEach-Object { '{0}\{1}' -f $_.Computer, $_.Gruppe }) -join ', ' } } |
    Format-Table -AutoSize -Wrap

# --- Auffaelligkeiten --------------------------------------------------------
$administratoren = $anzeige | Where-Object { $_.Gruppe -match '^(Administratoren|Administrators)$' }
if ($administratoren) {
    Write-Host '=== Administratoren je Computer ===' -ForegroundColor Cyan
    $administratoren | Sort-Object Computer, Mitglied | Format-Table Computer, Mitglied, Typ, Herkunft -AutoSize
}

Write-Host "Erfasste Mitgliedschaften: $($anzeige.Count)" -ForegroundColor White

if ($CsvPfad) {
    $daten | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
}
