# EXPLORATORY: verify we can read LLDP (switch name + port) host-side on node01 via pktmon,
# BEFORE building the full 8-port mapping tool. LLDP = EtherType 0x88CC, sent by Arista ~every 30s.
# Captures ~45s on node01 (both storage ports), converts to text, and shows any lines that look like
# the switch hostname or an Ethernet port id. This tells us the exact output format to parse.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('azl-node-01\Administrator',$pw)

$sb = {
  $etl = "C:\Windows\Temp\lldp_probe.etl"
  $txt = "C:\Windows\Temp\lldp_probe.txt"
  Remove-Item $etl,$txt -ErrorAction SilentlyContinue
  $out = [ordered]@{}
  # capabilities / help so we see exact supported flags (no guessing)
  $out.FilterHelp = (& pktmon filter add --help 2>&1 | Out-String)
  $out.Etl2txtHelp= (& pktmon etl2txt --help 2>&1 | Out-String)
  # component list to map packets -> adapter
  $out.List = (& pktmon list 2>&1 | Out-String)
  # set up LLDP-only capture
  & pktmon filter remove 2>&1 | Out-Null
  $out.FilterAdd = (& pktmon filter add LLDP --ethertype 0x88CC 2>&1 | Out-String)
  $out.Start = (& pktmon start --capture --pkt-size 0 --file-name $etl 2>&1 | Out-String)
  Start-Sleep -Seconds 45
  $out.Stop = (& pktmon stop 2>&1 | Out-String)
  $out.Convert = (& pktmon etl2txt $etl -o $txt 2>&1 | Out-String)
  if (Test-Path $txt) {
    $c = Get-Content $txt
    $out.TotalLines = $c.Count
    $out.Hits = ($c | Select-String -Pattern '7050sw|Ethernet\d+/|sw1|sw2' | Select-Object -First 40 | ForEach-Object { $_.Line }) -join "`n"
    $out.Head = ($c | Select-Object -First 60) -join "`n"
  } else {
    $out.TotalLines = 0
    $out.Hits = '(no text file produced)'
  }
  [pscustomobject]$out
}
$r = Invoke-Command azl-node-01.lab.example.com -Credential $cred -Authentication Negotiate -ScriptBlock $sb
"===== pktmon filter add --help ====="; $r.FilterHelp
"===== pktmon etl2txt --help ====="; $r.Etl2txtHelp
"===== filter add result ====="; $r.FilterAdd
"===== start ====="; $r.Start
"===== stop ====="; $r.Stop
"===== convert ====="; $r.Convert
"===== total lines: $($r.TotalLines) ====="
"===== HITS (switch name / port id) ====="; $r.Hits
"===== HEAD (first 60 lines) ====="; $r.Head
