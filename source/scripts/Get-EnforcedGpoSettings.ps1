<#
.SYNOPSIS
  Read the security settings of specific (enforced) GPOs directly from SYSVOL,
  without RSAT/GroupPolicy module, and flag anything that conflicts with Azure Local.

.DESCRIPTION
  For each GPO GUID, resolves the display name from AD, then reads the machine
  security template from SYSVOL:
    \\<domain>\SYSVOL\<domain>\Policies\{GUID}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf
  and extracts [Privilege Rights] (logon rights), [Service General Setting]
  (disabled services), and flags the settings Azure Local cares about:
    - Deny logon rights that could block the LCM account / cluster.
    - Disabled services Azure Local needs (WinRM, cluster, Hyper-V, etc.).
  Also notes whether a Registry.pol exists (admin-template settings - needs RSAT to fully decode).

.NOTES
  Read-only. ASCII only. Uses current Kerberos creds for SYSVOL/AD access.
#>
[CmdletBinding()]
param(
  [string]   $Server = 'corp.example.com',
  [string]   $Domain = 'corp.example.com',
  [string[]] $Guids = @(
    '00000000-0000-0000-0000-000000000008',
    '00000000-0000-0000-0000-000000000009',
    '00000000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000013',
    '00000000-0000-0000-0000-000000000014',
    '00000000-0000-0000-0000-000000000015'
  ),
  [string]   $OutDir = "$PSScriptRoot\..\out"
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

# Logon-right privileges relevant to Azure Local (deny = risk; grant = good).
$denyRights = 'SeDenyInteractiveLogonRight','SeDenyBatchLogonRight','SeDenyRemoteInteractiveLogonRight','SeDenyServiceLogonRight','SeDenyNetworkLogonRight'
$grantRights= 'SeInteractiveLogonRight','SeBatchLogonRight','SeRemoteInteractiveLogonRight','SeServiceLogonRight','SeNetworkLogonRight'
# Services Azure Local / clustering / management need running.
$criticalSvc = 'WinRM','ClusSvc','vmms','WMSvc','TermService','LanmanServer','LanmanWorkstation','Netlogon','gpsvc','BFE','mpssvc','Winmgmt','HvHost','nvspwmi'

function Parse-Ini([string[]]$lines) {
  $h = @{}; $sec = $null
  foreach ($l in $lines) {
    $t = $l.Trim()
    if ($t -match '^\[(.+)\]$') { $sec = $Matches[1]; $h[$sec] = @(); continue }
    if ($sec -and $t -and $t -notmatch '^;') { $h[$sec] += $t }
  }
  $h
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$domDn = 'DC=' + ($Domain -replace '\.', ',DC=')
$report = New-Object System.Collections.Generic.List[object]

foreach ($g in $Guids) {
  $name = $g
  try {
    $o = Get-ADObject -Server $Server -Identity "CN={$g},CN=Policies,CN=System,$domDn" -Properties displayName -ErrorAction Stop
    if ($o.displayName) { $name = $o.displayName }
  } catch { }

  $inf = "\\$Domain\SYSVOL\$Domain\Policies\{$g}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
  $regpol = "\\$Domain\SYSVOL\$Domain\Policies\{$g}\Machine\Registry.pol"

  Write-Host "`n==================================================================" -ForegroundColor Cyan
  Write-Host ("GPO: {0}" -f $name) -ForegroundColor Cyan
  Write-Host ("GUID: {0}" -f $g) -ForegroundColor DarkGray

  if (-not (Test-Path $inf)) {
    Write-Host "  (no GptTmpl.inf - no security-template settings in this GPO)" -ForegroundColor DarkGray
  } else {
    $ini = Parse-Ini (Get-Content $inf -ErrorAction SilentlyContinue)

    if ($ini['Privilege Rights']) {
      Write-Host "  [Privilege Rights]" -ForegroundColor Yellow
      foreach ($line in $ini['Privilege Rights']) {
        $key = ($line -split '=',2)[0].Trim()
        $isDeny  = $denyRights  -contains $key
        $isGrant = $grantRights -contains $key
        $color = if ($isDeny) { 'Red' } elseif ($isGrant) { 'Green' } else { 'Gray' }
        Write-Host "    $line" -ForegroundColor $color
        if ($isDeny -or $isGrant) {
          $report.Add([pscustomobject]@{ GPO=$name; Category='PrivilegeRight'; Setting=$key; Value=(($line -split '=',2)[1]).Trim(); Risk=$(if($isDeny){'REVIEW-DENY'}else{'grant'}) })
        }
      }
    }

    if ($ini['Service General Setting']) {
      $disabled = foreach ($line in $ini['Service General Setting']) {
        $parts = $line -split ','
        $svc = ($parts[0] -replace '"','').Trim()
        $startup = ($parts[1]).Trim()   # 4 = Disabled, 2 = Automatic, 3 = Manual
        if ($startup -eq '4' -and ($criticalSvc -contains $svc)) { $svc }
      }
      if ($disabled) {
        Write-Host "  [Service General Setting] CRITICAL services set DISABLED:" -ForegroundColor Red
        $disabled | ForEach-Object { Write-Host "    $_ = Disabled" -ForegroundColor Red; $report.Add([pscustomobject]@{ GPO=$name; Category='Service'; Setting=$_; Value='Disabled'; Risk='REVIEW-SVC' }) }
      } else {
        Write-Host "  [Service General Setting] present - no Azure-Local-critical service disabled" -ForegroundColor DarkGray
      }
    }
  }

  if (Test-Path $regpol) {
    $sz = (Get-Item $regpol).Length
    Write-Host "  Registry.pol present ($sz bytes) - admin-template settings; decode with RSAT Get-GPOReport for full detail." -ForegroundColor DarkYellow
    $report.Add([pscustomobject]@{ GPO=$name; Category='Registry.pol'; Setting='present'; Value="$sz bytes"; Risk='needs-RSAT' })
  }
}

Write-Host "`n================ SUMMARY (items to review) ================" -ForegroundColor Cyan
$flag = $report | Where-Object { $_.Risk -like 'REVIEW*' }
if ($flag) { $flag | Format-Table GPO,Category,Setting,Value,Risk -Auto | Out-String -Width 200 }
else { Write-Host "No deny-logon rights or critical-service-disable found in the enforced GPOs' security templates." -ForegroundColor Green }

$csv = Join-Path $OutDir ("_enforced-gpo-settings-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | Export-Csv -NoTypeInformation -Path $csv
Write-Host "Saved: $csv" -ForegroundColor Cyan
