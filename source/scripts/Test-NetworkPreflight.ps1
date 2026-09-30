<#
.SYNOPSIS
  Network pre-flight gate for Azure Local nodes. Verifies (and optionally enables)
  the physical NICs that the CRITICAL AzStackHci_Hardware_Test_NetAdapter check
  requires, per node, BEFORE committing to a deployment attempt.

.DESCRIPTION
  This is the network equivalent of the storage Phase 0a gate. It exists because
  the NetAdapter CRITICAL failure (Mellanox ConnectX-5 ports left DISABLED,
  PnP problem 22) was only caught late - there was no pre-flight gate forcing us
  to read it. See decisions/0010-mellanox-nic-disabled-not-missing.md.

  The validator's NIC gate filter (read from the module at runtime) is:
    NdisMedium -eq 0 -and Status -eq 'Up'
      -and NdisPhysicalMedium -eq 14 -and PnPDeviceID -notlike 'USB\*'
  This script reports, per candidate NIC, whether it satisfies that filter, and
  (with -EnableDisabled) enables any Mellanox/ConnectX device that is present but
  administratively disabled (PnP problem 22). Enabling is free, software-only, and
  reversible. It does NOT install drivers or change cabling.

  DRIVER CAVEAT (does NOT affect THIS gate, but blocks DEPLOY): a passing NIC may
  still run the INBOX Microsoft driver (DriverProvider=Microsoft), which MS Learn
  documents as unsupported for Azure Local deployment. This script REPORTS the
  DriverProvider so you can see which nodes still need the WinOF-2 swap, but it
  treats inbox as a PASS for the hardware gate (which is correct).

.PARAMETER NodeFqdn
  One or more node FQDNs. Defaults to all six lab nodes.

.PARAMETER EnableDisabled
  If set, enables any present-but-disabled Mellanox/ConnectX NIC (Enable-PnpDevice).
  Without it, the script is READ-ONLY (report only).

.EXAMPLE
  .\scripts\Test-NetworkPreflight.ps1 -NodeFqdn azl-node-02.lab.example.com          # report only
  .\scripts\Test-NetworkPreflight.ps1 -NodeFqdn azl-node-02.lab.example.com -EnableDisabled
#>
[CmdletBinding()]
param(
  [string[]] $NodeFqdn = @(
    'azl-node-01.lab.example.com','azl-node-02.lab.example.com','azl-node-03.lab.example.com',
    'azl-node-04.lab.example.com','azl-node-05.lab.example.com','azl-node-06.lab.example.com'
  ),
  [switch]   $EnableDisabled,
  [string]   $CredFile = (Join-Path $PSScriptRoot '..\.creds\azloc-local-admin.cred' | Resolve-Path -ErrorAction SilentlyContinue),
  [string]   $Username = 'Administrator'
)

$ErrorActionPreference = 'Stop'
if (-not $CredFile -or -not (Test-Path $CredFile)) { throw "CredFile not found: $CredFile" }
$pw = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())

foreach ($fqdn in $NodeFqdn) {
  $short = ($fqdn -split '\.')[0]
  $cred  = [pscredential]::new("$short\$Username", $pw)
  $opt   = New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 120000
  Write-Host "`n=== $short ===" -ForegroundColor Cyan
  try {
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -SessionOption $opt -ErrorAction Stop
  } catch {
    Write-Host "  UNREACHABLE: $($_.Exception.Message)" -ForegroundColor Red
    continue
  }

  try {
    $r = Invoke-Command -Session $s -ArgumentList ([bool]$EnableDisabled) -ScriptBlock {
      param($doEnable)

      # 1) Optionally enable disabled Mellanox/ConnectX PnP devices (problem 22).
      $enabled = @()
      if ($doEnable) {
        $disabled = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
          Where-Object { $_.FriendlyName -match 'Mellanox|ConnectX' -and $_.Status -eq 'Error' }
        foreach ($d in $disabled) {
          try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop; $enabled += $d.FriendlyName }
          catch { }
        }
        if ($enabled) { Start-Sleep -Seconds 5 }  # let the stack settle after enable
      }

      # 2) Evaluate every NIC against the validator's exact gate filter.
      $nics = foreach ($a in (Get-NetAdapter -ErrorAction SilentlyContinue)) {
        $drv  = $a.DriverProvider
        $passes = ($a.NdisMedium -eq 0) -and ($a.Status -eq 'Up') -and
                  ($a.NdisPhysicalMedium -eq 14) -and ($a.PnPDeviceID -notlike 'USB\*')
        [pscustomobject]@{
          Name         = $a.Name
          Status       = "$($a.Status)"
          LinkSpeed    = $a.LinkSpeed
          NdisMedium   = $a.NdisMedium
          PhysMedium   = $a.NdisPhysicalMedium
          DriverProv   = $drv
          Inbox        = ($drv -eq 'Microsoft')
          PassesGate   = $passes
        }
      }

      # 3) Also surface any Mellanox/ConnectX still in an error/disabled state.
      $stillDisabled = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Mellanox|ConnectX' -and $_.Status -eq 'Error' } |
        Select-Object -ExpandProperty FriendlyName

      [pscustomobject]@{
        Node          = $env:COMPUTERNAME
        Enabled       = $enabled
        Nics          = $nics
        StillDisabled = @($stillDisabled)
        GatePass      = [bool]($nics | Where-Object { $_.PassesGate })
      }
    }

    if ($r.Enabled) { Write-Host "  Enabled: $($r.Enabled -join ', ')" -ForegroundColor Green }
    $r.Nics | Sort-Object -Property PassesGate -Descending |
      Format-Table Name,Status,LinkSpeed,NdisMedium,PhysMedium,DriverProv,Inbox,PassesGate -AutoSize | Out-String | Write-Host

    if ($r.GatePass) {
      Write-Host "  GATE: PASS (>=1 NIC matches NdisMedium=0/Up/PhysMedium=14/non-USB)" -ForegroundColor Green
      if ($r.Nics | Where-Object { $_.PassesGate -and $_.Inbox }) {
        Write-Host "  NOTE: passing NIC(s) run the INBOX driver -> WinOF-2 swap still required before DEPLOY (not this gate)." -ForegroundColor Yellow
      }
    } else {
      Write-Host "  GATE: FAIL (no NIC matches the validator filter)" -ForegroundColor Red
      if ($r.StillDisabled) { Write-Host "  Mellanox/ConnectX still disabled: $($r.StillDisabled -join ', ') -> re-run with -EnableDisabled" -ForegroundColor Red }
    }
  }
  finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
  }
}
