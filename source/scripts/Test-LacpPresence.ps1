# Detect LACP on the switch side by capturing LACPDU frames arriving on the
# storage NICs. LACPDU dest MAC = 01-80-C2-00-00-02, EtherType 0x8809.
# If frames are seen, the switch port still has LACP configured. Read-only
# (short pktmon capture, filters reset after). ASCII only.
[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-01','azl-node-02'),
  [int]      $Seconds = 12,
  [string]   $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw  = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

$blk = {
  param($secs)
  $mac = '01-80-C2-00-00-02'
  $etl = Join-Path $env:TEMP 'lacp.etl'
  $txt = Join-Path $env:TEMP 'lacp.txt'
  if (-not (Get-Command pktmon.exe -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Node=$env:COMPUTERNAME; pktmon='MISSING'; LacpFrames=$null; Port3=$null; Port4=$null }
  }
  cmd /c "pktmon stop" *>$null
  Remove-Item $etl,$txt -ErrorAction SilentlyContinue
  cmd /c "pktmon filter remove" *>$null
  cmd /c "pktmon filter add LACP -m $mac" *>$null
  cmd /c "pktmon start --capture --file-name `"$etl`" --pkt-size 128" *>$null
  Start-Sleep -Seconds $secs
  cmd /c "pktmon stop" *>$null
  cmd /c "pktmon format `"$etl`" -o `"$txt`"" *>$null
  cmd /c "pktmon filter remove" *>$null
  $lines = Get-Content $txt -ErrorAction SilentlyContinue
  $pkts  = $lines | Where-Object { $_ -match '^\s*\d+\s' }
  [pscustomobject]@{
    Node       = $env:COMPUTERNAME
    pktmon     = 'ok'
    LacpFrames = @($pkts).Count
    Port3      = @($pkts | Where-Object { $_ -match 'Port3' }).Count
    Port4      = @($pkts | Where-Object { $_ -match 'Port4' }).Count
  }
}

foreach ($n in $Nodes) {
  $cred = [pscredential]::new("$n\Administrator", $pw)
  try {
    Invoke-Command -ComputerName "$n.lab.example.com" -Credential $cred -SessionOption $opt -ScriptBlock $blk -ArgumentList $Seconds -ErrorAction Stop |
      Select-Object Node, pktmon, LacpFrames, Port3, Port4
  } catch {
    [pscustomobject]@{ Node=$n; pktmon='ERR'; LacpFrames=$_.Exception.Message.Split([char]10)[0]; Port3=$null; Port4=$null }
  }
}
