# Detect LACP vs LLDP slow-protocol frames on the storage NICs.
# LACP  dst MAC 01-80-C2-00-00-02, EtherType 0x8809.
# LLDP  dst MAC 01-80-C2-00-00-0E, EtherType 0x88CC (positive control).
# LLDP present + LACP absent => capture works and LACP is OFF on the switch.
# Read-only short pktmon capture; filters reset after. ASCII only.
[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-01','azl-node-02'),
  [int]      $Seconds = 35,
  [string]   $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw  = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 180000

$blk = {
  param($secs)
  $etl = Join-Path $env:TEMP 'slow.etl'
  $txt = Join-Path $env:TEMP 'slow.txt'
  if (-not (Get-Command pktmon.exe -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Node=$env:COMPUTERNAME; pktmon='MISSING' }
  }
  cmd /c "pktmon stop" *>$null
  Remove-Item $etl,$txt -ErrorAction SilentlyContinue
  cmd /c "pktmon filter remove" *>$null
  cmd /c "pktmon filter add LACP -m 01-80-C2-00-00-02" *>$null
  cmd /c "pktmon filter add LLDP -m 01-80-C2-00-00-0E" *>$null
  cmd /c "pktmon start --capture --file-name `"$etl`" --pkt-size 128" *>$null
  Start-Sleep -Seconds $secs
  cmd /c "pktmon stop" *>$null
  cmd /c "pktmon format `"$etl`" -o `"$txt`"" *>$null
  cmd /c "pktmon filter remove" *>$null
  $t = (Get-Content $txt -Raw -ErrorAction SilentlyContinue)
  $lacp = ([regex]::Matches($t, '8809')).Count
  $lldp = ([regex]::Matches($t, '88CC|88cc')).Count
  [pscustomobject]@{
    Node       = $env:COMPUTERNAME
    pktmon     = 'ok'
    LACP_0x8809= $lacp
    LLDP_0x88CC= $lldp
    Verdict    = if ($lacp -gt 0) { 'LACP STILL ON' } elseif ($lldp -gt 0) { 'LACP off (LLDP seen = capture ok)' } else { 'INCONCLUSIVE (no slow-proto frames captured)' }
  }
}

foreach ($n in $Nodes) {
  $cred = [pscredential]::new("$n\Administrator", $pw)
  try {
    Invoke-Command -ComputerName "$n.lab.example.com" -Credential $cred -SessionOption $opt -ScriptBlock $blk -ArgumentList $Seconds -ErrorAction Stop |
      Select-Object Node, pktmon, LACP_0x8809, LLDP_0x88CC, Verdict
  } catch {
    [pscustomobject]@{ Node=$n; pktmon='ERR'; LACP_0x8809=$null; LLDP_0x88CC=$null; Verdict=$_.Exception.Message.Split([char]10)[0] }
  }
}
