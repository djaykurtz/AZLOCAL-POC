[CmdletBinding()]
param(
  [string[]]$NodeFqdns = @(
    'azl-node-01.lab.example.com','azl-node-02.lab.example.com',
    'azl-node-03.lab.example.com','azl-node-04.lab.example.com',
    'azl-node-05.lab.example.com','azl-node-06.lab.example.com'
  ),
  [string]$Username = 'Administrator',
  [string]$CredFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.creds\azloc-local-admin.cred'),
  [string]$OutDir   = (Join-Path (Split-Path -Parent $PSScriptRoot) 'out')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$cipher = Get-Content -Path $CredFile -Raw
$pw     = ConvertTo-SecureString $cipher.Trim()

$rows = foreach ($fqdn in $NodeFqdns) {
  $short = ($fqdn -split '\.')[0]
  $cred  = [pscredential]::new("$short\$Username", $pw)

  try {
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop
  } catch {
    [pscustomobject]@{ Node=$short; Source='SESSION'; Result="ERROR: $($_.Exception.Message)" }
    continue
  }

  try {
    $payload = Invoke-Command -Session $s -ScriptBlock {
      $out = [ordered]@{}

      # 1) Win32_Processor (what we already have - the suspect signal)
      $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
      $out.W32_VirtFW   = $cpu.VirtualizationFirmwareEnabled
      $out.W32_SLAT     = $cpu.SecondLevelAddressTranslationExtensions
      $out.W32_VMMon    = $cpu.VMMonitorModeExtensions

      # 2) Get-ComputerInfo - reads the Hyper-V requirements code path
      $ci = Get-ComputerInfo -Property `
        HyperVisorPresent, `
        HyperVRequirementVirtualizationFirmwareEnabled, `
        HyperVRequirementSecondLevelAddressTranslation, `
        HyperVRequirementVMMonitorModeExtensions, `
        HyperVRequirementDataExecutionPreventionAvailable
      $out.GCI_HVPresent   = $ci.HyperVisorPresent
      $out.GCI_VirtFW      = $ci.HyperVRequirementVirtualizationFirmwareEnabled
      $out.GCI_SLAT        = $ci.HyperVRequirementSecondLevelAddressTranslation
      $out.GCI_VMMon       = $ci.HyperVRequirementVMMonitorModeExtensions
      $out.GCI_DEP         = $ci.HyperVRequirementDataExecutionPreventionAvailable

      # 3) bcdedit - is the OS even trying to launch the hypervisor at boot?
      $bcd = & bcdedit /enum '{current}' 2>&1 | Out-String
      $m   = [regex]::Match($bcd, '(?im)^\s*hypervisorlaunchtype\s+(\S+)')
      $out.BCD_HVLaunch = if ($m.Success) { $m.Groups[1].Value } else { '(not set)' }

      # 4) Hyper-V feature + service state
      try {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Hypervisor' -ErrorAction Stop
        $out.HV_FeatureState = $feat.State
      } catch {
        $out.HV_FeatureState = "(err: $($_.Exception.Message.Split([char]10)[0]))"
      }
      $vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
      $out.HV_VmmsState = if ($vmms) { $vmms.Status.ToString() } else { '(not installed)' }

      # 5) systeminfo - independent code path, reports CPUID-derived facts
      $si = & systeminfo.exe 2>&1 | Out-String
      $hvBlock = ($si -split "(?m)^Hyper-V Requirements:\s*")[1]
      if ($hvBlock) {
        $out.SI_HyperVBlock = ($hvBlock -split "(?m)^\S")[0].Trim()
      } else {
        $out.SI_HyperVBlock = '(no Hyper-V Requirements block)'
      }

      [pscustomobject]$out
    }

    [pscustomobject]@{
      Node              = $short
      # Win32_Processor (suspect)
      W32_VirtFW        = $payload.W32_VirtFW
      W32_SLAT          = $payload.W32_SLAT
      # Get-ComputerInfo
      GCI_HVPresent     = $payload.GCI_HVPresent
      GCI_VirtFW        = $payload.GCI_VirtFW
      GCI_SLAT          = $payload.GCI_SLAT
      # bcdedit / hypervisor launch
      BCD_HVLaunch      = $payload.BCD_HVLaunch
      HV_FeatureState   = $payload.HV_FeatureState
      HV_VmmsState      = $payload.HV_VmmsState
      # systeminfo block (multi-line, keep verbatim in JSON dump only)
      SI_HyperVBlock    = $payload.SI_HyperVBlock
    }
  } catch {
    [pscustomobject]@{ Node=$short; Source='INVOKE'; Result="ERROR: $($_.Exception.Message)" }
  } finally {
    Remove-PSSession $s -ErrorAction SilentlyContinue
  }
}

# Compact table to console (drops the long systeminfo block)
$table = $rows | Select-Object Node, W32_VirtFW, W32_SLAT, GCI_HVPresent, GCI_VirtFW, GCI_SLAT, BCD_HVLaunch, HV_FeatureState, HV_VmmsState
$tableText = $table | Format-Table -AutoSize | Out-String -Width 200
$tableText | Tee-Object -FilePath (Join-Path $OutDir '_virt_signals.txt')

# Full dump (with systeminfo Hyper-V block per node) to JSON
$rows | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutDir '_virt_signals.json')

# Per-node systeminfo blocks to a readable txt
$siOut = foreach ($r in $rows) {
  "===== $($r.Node) — systeminfo Hyper-V Requirements ====="
  $r.SI_HyperVBlock
  ''
}
$siOut -join [Environment]::NewLine | Set-Content -Path (Join-Path $OutDir '_virt_signals_systeminfo.txt')
