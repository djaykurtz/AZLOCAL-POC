<#
.SYNOPSIS
  Collect NVMe temperature and thermal-throttle history from the Azure Local nodes.

.DESCRIPTION
  We moved from the ASUS Hyper M.2 (active fan, per-slot heatsinks) to the RIITOP quad carrier
  (passive heatsinks only) for mechanical fit in the 1U chassis, per ADR 0008. Nobody measured
  what that cost thermally. This reads it off the drives.

  Two tiers, so a failure in the second still leaves usable data:

    Tier 1  Get-StorageReliabilityCounter. Current and lifetime-max temperature. Always available.
    Tier 2  Raw NVMe SMART/Health log page 0x02 and Identify Controller, via
            IOCTL_STORAGE_QUERY_PROPERTY. This is the tier that matters, because it carries the
            two counters that answer the question directly:
              WarningCompositeTempTime   minutes spent at or above the drive's own WCTEMP
              CriticalCompositeTempTime  minutes spent at or above the drive's own CCTEMP
            Any non-zero value there is the drive telling you it throttled.

  Thresholds are read from the device Identify Controller rather than assumed, so the verdict is
  against the manufacturer's own limit for the exact part fitted.

.PARAMETER Nodes
  Two digit node numbers. Defaults to the four cluster members.

.PARAMETER CredFile
  DPAPI protected password file for sim\labadmin. Per docs/access/credential-map.md that is
  the working way to reach the nodes over WinRM; the local Administrator path stopped working once
  the nodes were domain joined by deployment.

.PARAMETER Csv
  Optional path to also write the per-drive rows for trending across runs.

.EXAMPLE
  .\Get-NvmeThermals.ps1

.EXAMPLE
  .\Get-NvmeThermals.ps1 -Csv ..\docs\storage-imaging\nvme-thermals-20260903.csv

.NOTES
  Read only. Issues no writes and no admin state changes on the nodes.
#>

[CmdletBinding()]
param(
  [string[]] $Nodes    = @('01', '02', '04', '06'),
  [string]   $CredFile = "$PSScriptRoot\..\.creds\sim-example-internal-admin.cred",
  [string]   $User     = 'sim\labadmin',
  [string]   $Csv
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CredFile)) { throw "Credential file not found: $CredFile" }
$pw   = ConvertTo-SecureString ((Get-Content $CredFile -Raw).Trim())
$cred = [pscredential]::new($User, $pw)

$probe = {
  $ErrorActionPreference = 'Continue'

  # NVMe SMART lives behind IOCTL_STORAGE_QUERY_PROPERTY with a protocol specific payload. There is
  # no cmdlet for the throttle counters, so this is the only way to reach them without smartctl.
  $cs = @'
using System;
using System.Runtime.InteropServices;
public static class Nvme {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr sec,
    uint disp, uint flags, IntPtr templ);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool DeviceIoControl(IntPtr h, uint code, byte[] inBuf, int inSize,
    byte[] outBuf, int outSize, ref int returned, IntPtr overlapped);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool CloseHandle(IntPtr h);

  // dataType: 0 = Identify, 2 = LogPage.  requestValue: 1 = controller identify, 0x02 = SMART log.
  public static byte[] Query(int driveNumber, int dataType, int requestValue) {
    const uint IOCTL = 0x2D1400;              // IOCTL_STORAGE_QUERY_PROPERTY
    const int  PROTO_DATA_OFFSET = 40;        // sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
    const int  PAYLOAD = 4096;
    IntPtr h = CreateFileW(@"\\.\PhysicalDrive" + driveNumber, 0xC0000000u, 3u,
      IntPtr.Zero, 3u, 0u, IntPtr.Zero);
    if (h == (IntPtr)(-1)) return null;
    try {
      int size = 8 + PROTO_DATA_OFFSET + PAYLOAD;
      byte[] buf = new byte[size];
      BitConverter.GetBytes(50).CopyTo(buf, 0);   // StorageDeviceProtocolSpecificProperty
      BitConverter.GetBytes(0).CopyTo(buf, 4);    // PropertyStandardQuery
      int p = 8;
      BitConverter.GetBytes(3).CopyTo(buf, p + 0);                  // ProtocolTypeNvme
      BitConverter.GetBytes(dataType).CopyTo(buf, p + 4);
      BitConverter.GetBytes(requestValue).CopyTo(buf, p + 8);
      BitConverter.GetBytes(0).CopyTo(buf, p + 12);
      BitConverter.GetBytes(PROTO_DATA_OFFSET).CopyTo(buf, p + 16);
      BitConverter.GetBytes(PAYLOAD).CopyTo(buf, p + 20);
      int got = 0;
      bool ok = DeviceIoControl(h, IOCTL, buf, size, buf, size, ref got, IntPtr.Zero);
      if (!ok) return null;
      int off = BitConverter.ToInt32(buf, 8 + 16);
      int len = BitConverter.ToInt32(buf, 8 + 20);
      if (len <= 0 || 8 + off + len > size) return null;
      byte[] outp = new byte[len];
      Array.Copy(buf, 8 + off, outp, 0, len);
      return outp;
    } finally { CloseHandle(h); }
  }
}
'@
  $haveNative = $true
  try { Add-Type -TypeDefinition $cs -ErrorAction Stop } catch { $haveNative = $false }

  $k2c = { param($k) if ($k -gt 0) { [int]$k - 273 } else { $null } }

  $inPool = @{}
  foreach ($sp in (Get-StoragePool -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -ne 'Primordial' })) {
    foreach ($d in (Get-PhysicalDisk -StoragePool $sp -ErrorAction SilentlyContinue)) {
      $inPool[[string]$d.UniqueId] = $sp.FriendlyName
    }
  }

  # Get-PhysicalDisk is cluster wide on S2D, so one node returns every drive in the cluster. Neither
  # Get-StorageNode piping nor -PhysicallyConnected scoping returns pool members, but the reverse
  # association from disk to node does, so that is what attributes each drive to its chassis.
  $nvme = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'NVMe' }

  # Pool members are claimed by Storage Spaces and have no \\.\PhysicalDriveN of their own, so the raw
  # SMART path reaches only the drives Windows still owns directly. Anything else gets the counter.
  $localIdx = @{}
  foreach ($w in (Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)) {
    $localIdx[[string]$w.Index] = $true
  }

  foreach ($pd in ($nvme | Sort-Object { [int]$_.DeviceId })) {
    $num = -1
    [void][int]::TryParse([string]$pd.DeviceId, [ref]$num)
    $rc  = $pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    $owner = ($pd | Get-StorageNode -PhysicallyConnected -ErrorAction SilentlyContinue | Select-Object -First 1).Name
    $short = if ($owner) { ($owner -split '\.')[0].ToUpper() } else { 'unknown' }
    $isLocal = $localIdx.ContainsKey([string]$num) -and $short -eq $env:COMPUTERNAME.ToUpper()
    $sys = if ($isLocal) { Get-Disk -Number $num -ErrorAction SilentlyContinue } else { $null }

    $bus = ''
    if ($pd.PhysicalLocation -match 'Bus (\d+)') { $bus = $Matches[1] }

    $row = [ordered]@{
      Node        = $short
      DeviceId    = $pd.DeviceId
      Model       = ($pd.FriendlyName -replace '\s+', ' ').Trim()
      Serial      = if ($pd.SerialNumber) { $pd.SerialNumber.Trim() } else { '' }
      Role        = if ($sys -and ($sys.IsBoot -or $sys.IsSystem)) { 'BOOT' } else { 'data' }
      Pool        = if ($inPool.ContainsKey([string]$pd.UniqueId)) { $inPool[[string]$pd.UniqueId] } else { '' }
      SizeGB      = [math]::Round($pd.Size / 1GB, 0)
      Bus         = $bus
      Location    = $pd.PhysicalLocation
      TempC       = if ($rc) { $rc.Temperature } else { $null }
      TempMaxC    = if ($rc) { $rc.TemperatureMax } else { $null }
      SmartTempC  = $null
      Sensors     = ''
      WarnTempC   = $null
      CritTempC   = $null
      WarnMinutes = $null
      CritMinutes = $null
      PowerOnHrs  = $null
      PctUsed     = $null
      SparePct    = $null
      TBWritten   = $null
      CritWarnBits = $null
      Source      = 'reliability-counter'
      Note        = ''
    }

    if ($haveNative -and $isLocal) {
      $smart = [Nvme]::Query($num, 2, 0x02)
      if ($smart -and $smart.Length -ge 216) {
        $row.CritWarnBits = '0x{0:X2}' -f $smart[0]
        $row.SmartTempC   = & $k2c ([BitConverter]::ToUInt16($smart, 1))
        $row.SparePct     = [int]$smart[3]
        $row.PctUsed      = [int]$smart[5]
        # Data Units Written counts 1000 x 512 byte units, so this is real host writes over the drive's life.
        $row.TBWritten    = [math]::Round(([BitConverter]::ToUInt64($smart, 48) * 512000.0) / 1TB, 2)
        $row.PowerOnHrs   = [BitConverter]::ToUInt64($smart, 128)
        $row.WarnMinutes  = [BitConverter]::ToUInt32($smart, 192)
        $row.CritMinutes  = [BitConverter]::ToUInt32($smart, 196)
        $sens = for ($i = 0; $i -lt 8; $i++) {
          $v = & $k2c ([BitConverter]::ToUInt16($smart, 200 + ($i * 2)))
          if ($null -ne $v) { $v }
        }
        $row.Sensors = ($sens -join '/')
        $row.Source  = 'nvme-smart-log'
      } else {
        $row.Note = 'SMART query failed'
      }
      $idc = [Nvme]::Query($num, 0, 1)
      if ($idc -and $idc.Length -ge 270) {
        $row.WarnTempC = & $k2c ([BitConverter]::ToUInt16($idc, 266))   # WCTEMP
        $row.CritTempC = & $k2c ([BitConverter]::ToUInt16($idc, 268))   # CCTEMP
      }
    } else {
      $row.Note = 'pooled, temperature only'
    }
    if ($null -eq $row.PowerOnHrs -and $rc) { $row.PowerOnHrs = $rc.PowerOnHours }

    [pscustomobject]$row
  }
}

# One node returns the whole cluster, so this stops at the first that answers.
$all = $null
foreach ($n in $Nodes) {
  $nn    = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"
  $fqdn  = "$short.lab.example.com"

  Write-Host "querying cluster via $short ..." -ForegroundColor DarkGray
  $s = $null
  try {
    $s = New-PSSession -ComputerName $fqdn -Credential $cred -Authentication Negotiate -ErrorAction Stop
  } catch {
    Write-Warning "$short : $($_.Exception.Message)"
    continue
  }
  try   { $all = Invoke-Command -Session $s -ScriptBlock $probe }
  finally { Remove-PSSession $s }
  if ($all) { break }
}

if (-not $all) { Write-Warning 'No data collected.'; return }

"`n=== NVMe TEMPERATURES ==="
"TempMax is reported as 83 by every drive here, which is the rated ceiling rather than a recorded high."
$all | Sort-Object Node, DeviceId | Format-Table -Auto `
  Node, DeviceId, Role, Bus,
  @{ n = 'Model'; e = { if ($_.Model.Length -gt 20) { $_.Model.Substring(0, 20) } else { $_.Model } } },
  @{ n = 'TempC'; e = { if ($null -ne $_.SmartTempC) { $_.SmartTempC } else { $_.TempC } } },
  @{ n = 'RatedMax'; e = { $_.TempMaxC } },
  @{ n = 'TBW'; e = { $_.TBWritten } },
  @{ n = 'Used%'; e = { $_.PctUsed } },
  @{ n = 'Hrs'; e = { $_.PowerOnHrs } },
  Note

"`n=== TEMPERATURE BY CARRIER SLOT (bus 180/181/182 are the three M.2 positions) ==="
$all | Where-Object { $_.Role -eq 'data' -and $_.Bus } | Group-Object Bus | Sort-Object Name | ForEach-Object {
  $t = $_.Group | ForEach-Object { if ($null -ne $_.SmartTempC) { $_.SmartTempC } else { $_.TempC } } | Where-Object { $null -ne $_ }
  if ($t) {
    [pscustomobject]@{
      Bus    = $_.Name
      Drives = $t.Count
      MinC   = ($t | Measure-Object -Minimum).Minimum
      AvgC   = [math]::Round(($t | Measure-Object -Average).Average, 1)
      MaxC   = ($t | Measure-Object -Maximum).Maximum
    }
  }
} | Format-Table -Auto

"`n=== SPREAD PER NODE (a hot outlier is a carrier airflow problem, not a drive problem) ==="
$all | Where-Object { $_.Role -eq 'data' } | Group-Object Node | ForEach-Object {
  $t = $_.Group | ForEach-Object { if ($null -ne $_.SmartTempC) { $_.SmartTempC } else { $_.TempC } } |
       Where-Object { $null -ne $_ }
  if ($t) {
    $mn = ($t | Measure-Object -Minimum).Minimum
    $mx = ($t | Measure-Object -Maximum).Maximum
    [pscustomobject]@{
      Node = $_.Name; DataDisks = $_.Group.Count; MinC = $mn; MaxC = $mx; SpreadC = $mx - $mn
    }
  }
} | Format-Table -Auto

if ($Csv) {
  $all | Export-Csv -NoTypeInformation -Path $Csv
  Write-Host "wrote $Csv" -ForegroundColor Green
}
