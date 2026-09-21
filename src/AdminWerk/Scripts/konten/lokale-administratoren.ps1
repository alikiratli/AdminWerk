<#
.SYNOPSIS
    Listet die Mitglieder der lokalen Administratorengruppe auf.
.DESCRIPTION
    Verwendet die SID S-1-5-32-544 statt des Gruppennamens und funktioniert
    dadurch unabhaengig von der Systemsprache. Zu lokalen Konten werden
    Zusatzinformationen wie letzte Anmeldung und Kennwortalter ermittelt.
.EXAMPLE
    .\lokale-administratoren.ps1 -Computername SRV01, SRV02
#>
[CmdletBinding()]
param(
    [string[]]$Computername = $env:COMPUTERNAME
)

foreach ($computer in $Computername) {
    Write-Host "`n=== Lokale Administratoren: $computer ===`n" -ForegroundColor Cyan

    try {
        $mitglieder = Invoke-Command -ComputerName $computer -ScriptBlock {
            Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
        } -ErrorAction Stop
    }
    catch {
        # Fallback fuer den lokalen Rechner ohne WinRM
        if ($computer -eq $env:COMPUTERNAME) {
            $mitglieder = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
        }
        else {
            Write-Warning "$computer : $($_.Exception.Message)"
            continue
        }
    }

    $bericht = foreach ($mitglied in $mitglieder) {
        # Im Muster muss der Backslash verdoppelt werden: einzeln leitet er eine
        # Escapefolge ein und ist am Musterende ungueltig.
        $kontoname = ($mitglied.Name -split '\\')[-1]
        $lokal = if ($mitglied.PrincipalSource -eq 'Local') {
            Get-LocalUser -Name $kontoname -ErrorAction SilentlyContinue
        }

        [PSCustomObject]@{
            Name            = $mitglied.Name
            Typ             = $mitglied.ObjectClass
            Herkunft        = $mitglied.PrincipalSource
            Aktiviert       = if ($lokal) { $lokal.Enabled } else { '-' }
            LetzteAnmeldung = if ($lokal) { $lokal.LastLogon } else { '-' }
            KennwortGesetzt = if ($lokal) { $lokal.PasswordLastSet } else { '-' }
        }
    }

    $bericht | Format-Table -AutoSize
    Write-Host "Mitglieder gesamt: $($bericht.Count)" -ForegroundColor White

    if ($bericht.Count -gt 3) {
        Write-Warning 'Mehr als drei Mitglieder - Berechtigungskonzept pruefen.'
    }
}
