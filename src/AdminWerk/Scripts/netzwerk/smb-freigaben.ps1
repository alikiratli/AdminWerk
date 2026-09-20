<#
.SYNOPSIS
    Dokumentiert alle SMB-Freigaben samt Freigabe- und NTFS-Berechtigungen.
.DESCRIPTION
    Listet Freigaben, deren Zugriffsrechte sowie die aktuell verbundenen Sitzungen.
    Administrative Freigaben (C$, ADMIN$) werden standardmaessig ausgeblendet.
.EXAMPLE
    .\smb-freigaben.ps1 -MitAdminFreigaben
#>
[CmdletBinding()]
param(
    [switch]$MitAdminFreigaben
)

$freigaben = Get-SmbShare
if (-not $MitAdminFreigaben) {
    $freigaben = $freigaben | Where-Object { $_.Name -notlike '*$' }
}

Write-Host "`n=== SMB-Freigaben auf $env:COMPUTERNAME ===`n" -ForegroundColor Cyan

foreach ($freigabe in $freigaben) {
    Write-Host ('{0}  ->  {1}' -f $freigabe.Name, $freigabe.Path) -ForegroundColor White
    if ($freigabe.Description) {
        Write-Host "  Beschreibung: $($freigabe.Description)" -ForegroundColor DarkGray
    }

    $zugriff = Get-SmbShareAccess -Name $freigabe.Name -ErrorAction SilentlyContinue
    if ($zugriff) {
        Write-Host '  Freigabeberechtigungen:' -ForegroundColor DarkGray
        $zugriff | ForEach-Object {
            Write-Host ('    {0,-45} {1} / {2}' -f $_.AccountName, $_.AccessControlType, $_.AccessRight)
        }
    }

    if (Test-Path -Path $freigabe.Path -ErrorAction SilentlyContinue) {
        $ntfs = (Get-Acl -Path $freigabe.Path).Access |
            Where-Object { -not $_.IsInherited -or $_.IdentityReference -notmatch 'NT AUTHORITY|BUILTIN' } |
            Select-Object -First 8

        if ($ntfs) {
            Write-Host '  NTFS-Berechtigungen (Auszug):' -ForegroundColor DarkGray
            $ntfs | ForEach-Object {
                Write-Host ('    {0,-45} {1} / {2}' -f $_.IdentityReference, $_.AccessControlType, $_.FileSystemRights)
            }
        }
    }

    Write-Host ''
}

Write-Host '=== Aktive Sitzungen ===' -ForegroundColor Cyan
$sitzungen = Get-SmbSession -ErrorAction SilentlyContinue
if ($sitzungen) {
    $sitzungen | Select-Object ClientComputerName, ClientUserName, NumOpens, SecondsIdle | Format-Table -AutoSize
}
else {
    Write-Host 'Keine aktiven Sitzungen.' -ForegroundColor DarkGray
}
