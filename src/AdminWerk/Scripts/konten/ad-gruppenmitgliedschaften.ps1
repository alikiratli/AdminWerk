<#
.SYNOPSIS
    Prueft Gruppenmitgliedschaften im Active Directory aus drei Blickrichtungen.
.DESCRIPTION
    Beantwortet die drei Fragen, die im Alltag wirklich gestellt werden:
    - Wer ist in dieser Gruppe? (auch ueber verschachtelte Gruppen hinweg)
    - In welchen Gruppen ist dieser Benutzer? (direkt und geerbt)
    - Welche Gruppen sind leer, verschachtelt oder auffaellig gross?

    Ohne Parameter laeuft die Gesamtuebersicht ueber alle Gruppen.
.NOTES
    Benoetigt das Modul ActiveDirectory (RSAT).
.EXAMPLE
    .\ad-gruppenmitgliedschaften.ps1 -Gruppe "Vertrieb"
.EXAMPLE
    .\ad-gruppenmitgliedschaften.ps1 -Benutzer m.mustermann
.EXAMPLE
    .\ad-gruppenmitgliedschaften.ps1 -CsvPfad C:\Berichte\gruppen.csv
#>
[CmdletBinding()]
param(
    [string[]]$Gruppe,

    [string[]]$Benutzer,

    [string]$Suchbasis,

    # Ab welcher Mitgliederzahl eine Gruppe als auffaellig gross gilt.
    [int]$GrossAbMitgliedern = 100,

    [string]$CsvPfad
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'Das Modul "ActiveDirectory" ist nicht verfuegbar. Bitte RSAT installieren.'
}

Import-Module ActiveDirectory -ErrorAction Stop

# ============ Sicht 1: Wer ist in dieser Gruppe? =============================
if ($Gruppe) {
    foreach ($name in $Gruppe) {
        $adGruppe = Get-ADGroup -Filter { Name -eq $name -or SamAccountName -eq $name } -Properties Description, GroupCategory, GroupScope, whenCreated -ErrorAction SilentlyContinue

        if (-not $adGruppe) {
            Write-Warning "Gruppe '$name' nicht gefunden."
            continue
        }

        Write-Host "`n=== Gruppe: $($adGruppe.Name) ===" -ForegroundColor Cyan
        Write-Host "Typ: $($adGruppe.GroupCategory) / $($adGruppe.GroupScope)"
        if ($adGruppe.Description) { Write-Host "Beschreibung: $($adGruppe.Description)" }
        Write-Host "Erstellt: $($adGruppe.whenCreated)`n"

        $direkt   = @(Get-ADGroupMember -Identity $adGruppe -ErrorAction SilentlyContinue)
        $rekursiv = @(Get-ADGroupMember -Identity $adGruppe -Recursive -ErrorAction SilentlyContinue)

        Write-Host "--- Direkte Mitglieder: $($direkt.Count) ---" -ForegroundColor White
        $direkt | Select-Object Name, SamAccountName, objectClass | Sort-Object objectClass, Name | Format-Table -AutoSize

        $verschachtelt = $direkt | Where-Object objectClass -eq 'group'
        if ($verschachtelt) {
            Write-Host "--- Enthaltene Gruppen: $($verschachtelt.Count) ---" -ForegroundColor White
            $verschachtelt | Select-Object Name | Format-Table -AutoSize
            Write-Host "Effektive Mitglieder inklusive Verschachtelung: $($rekursiv.Count)" -ForegroundColor Yellow
        }
    }
}

# ============ Sicht 2: In welchen Gruppen ist dieser Benutzer? ===============
if ($Benutzer) {
    foreach ($name in $Benutzer) {
        $konto = Get-ADUser -Filter { SamAccountName -eq $name } -Properties MemberOf, PrimaryGroup, Department, Title -ErrorAction SilentlyContinue

        if (-not $konto) {
            Write-Warning "Benutzer '$name' nicht gefunden."
            continue
        }

        Write-Host "`n=== Benutzer: $($konto.Name) ($($konto.SamAccountName)) ===" -ForegroundColor Cyan
        if ($konto.Department) { Write-Host "Abteilung: $($konto.Department)" }
        if ($konto.Title)      { Write-Host "Position: $($konto.Title)" }
        Write-Host ''

        $direkt = foreach ($dn in $konto.MemberOf) {
            $g = Get-ADGroup -Identity $dn -Properties Description -ErrorAction SilentlyContinue
            if ($g) {
                [PSCustomObject]@{
                    Gruppe = $g.Name; Typ = '{0}/{1}' -f $g.GroupCategory, $g.GroupScope
                    Herkunft = 'direkt'; Beschreibung = $g.Description
                }
            }
        }

        # Geerbte Mitgliedschaften: Gruppen, in denen die direkten Gruppen wiederum Mitglied sind.
        $geerbt = @()

        foreach ($dn in $konto.MemberOf) {
            $eltern = Get-ADGroup -Identity $dn -Properties MemberOf -ErrorAction SilentlyContinue
            foreach ($uebergeordnet in $eltern.MemberOf) {
                $g = Get-ADGroup -Identity $uebergeordnet -Properties Description -ErrorAction SilentlyContinue
                if ($g -and $g.Name -notin $direkt.Gruppe) {
                    $geerbt += [PSCustomObject]@{
                        Gruppe = $g.Name; Typ = '{0}/{1}' -f $g.GroupCategory, $g.GroupScope
                        Herkunft = "ueber $($eltern.Name)"; Beschreibung = $g.Description
                    }
                }
            }
        }

        $alle = @($direkt) + @($geerbt) | Sort-Object Gruppe -Unique
        $alle | Format-Table Gruppe, Typ, Herkunft, Beschreibung -AutoSize -Wrap
        Write-Host "Mitgliedschaften gesamt: $($alle.Count) (davon $(@($geerbt).Count) geerbt)" -ForegroundColor White
    }
}

# ============ Sicht 3: Gesamtuebersicht ======================================
if (-not $Gruppe -and -not $Benutzer) {
    $parameter = @{ Filter = '*'; Properties = 'Description', 'Members', 'whenCreated', 'GroupCategory', 'GroupScope' }
    if ($Suchbasis) { $parameter['SearchBase'] = $Suchbasis }

    Write-Host "`nLese alle Gruppen ..." -ForegroundColor Cyan
    $alleGruppen = Get-ADGroup @parameter

    $uebersicht = foreach ($g in $alleGruppen) {
        [PSCustomObject]@{
            Gruppe       = $g.Name
            Typ          = $g.GroupCategory
            Bereich      = $g.GroupScope
            Mitglieder   = @($g.Members).Count
            Erstellt     = $g.whenCreated
            Beschreibung = $g.Description
            OU           = ($g.DistinguishedName -split ',', 2)[1]
        }
    }

    Write-Host "`n=== Groesste Gruppen ===" -ForegroundColor Cyan
    $uebersicht | Sort-Object Mitglieder -Descending | Select-Object -First 20 |
        Format-Table Gruppe, Typ, Bereich, Mitglieder, Beschreibung -AutoSize -Wrap

    Write-Host '=== Leere Gruppen ===' -ForegroundColor Cyan
    $leer = $uebersicht | Where-Object Mitglieder -eq 0
    if ($leer) {
        $leer | Sort-Object Erstellt | Format-Table Gruppe, Typ, Erstellt, OU -AutoSize -Wrap
        Write-Warning "$($leer.Count) Gruppen ohne Mitglieder - Aufraeumkandidaten."
    }
    else { Write-Host 'Keine' -ForegroundColor Green }

    Write-Host "=== Auffaellig grosse Gruppen (ab $GrossAbMitgliedern Mitgliedern) ===" -ForegroundColor Cyan
    $gross = $uebersicht | Where-Object Mitglieder -ge $GrossAbMitgliedern
    if ($gross) {
        $gross | Sort-Object Mitglieder -Descending | Format-Table Gruppe, Mitglieder, Bereich, Beschreibung -AutoSize -Wrap
        Write-Host 'Sehr grosse Gruppen deuten oft auf ein zu grobes Berechtigungskonzept hin.' -ForegroundColor Yellow
    }
    else { Write-Host 'Keine' -ForegroundColor Green }

    Write-Host "`nGruppen gesamt: $($uebersicht.Count)" -ForegroundColor White

    if ($CsvPfad) {
        $uebersicht | Export-Csv -Path $CsvPfad -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        Write-Host "CSV-Export: $CsvPfad" -ForegroundColor Green
    }
}
