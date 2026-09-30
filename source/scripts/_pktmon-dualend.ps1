# Dual-end pktmon: capture on node01 (sender) AND node02 (receiver) during the same
# flood, both filtered to node01's Port3 MAC. Count REAL packet records (PktGroupId).
#  node01 count > 0, node02 = 0  -> node01 emits, frames lost in fabric (switch not fwd / node02 HW drop)
#  node01 = 0                    -> node01 not emitting at all (host TX tagging fails)
#  both > 0                      -> frames traverse; ARP failure is something else
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$ca = [pscredential]::new("azl-node-01\Administrator",$pw)
$cb = [pscredential]::new("azl-node-02\Administrator",$pw)
$mac = '00-00-5E-00-53-01'   # node01 Port3

$startCap = {
  param($mac,$tag)
  pktmon stop 2>&1 | Out-Null
  pktmon filter remove 2>&1 | Out-Null
  pktmon filter add $tag -m $mac 2>&1 | Out-Null
  Remove-Item C:\Windows\Temp\dual.etl -ErrorAction SilentlyContinue
  pktmon start --capture --pkt-size 0 --file-name C:\Windows\Temp\dual.etl 2>&1 | Out-Null
  'started'
}
$stopCount = {
  pktmon stop 2>&1 | Out-Null
  Remove-Item C:\Windows\Temp\dual.txt -ErrorAction SilentlyContinue
  pktmon etl2txt C:\Windows\Temp\dual.etl --out C:\Windows\Temp\dual.txt 2>&1 | Out-Null
  $l = if (Test-Path C:\Windows\Temp\dual.txt) { Get-Content C:\Windows\Temp\dual.txt } else { @() }
  $pkts = $l | Where-Object { $_ -match 'PktGroupId' }
  # try to surface ethertype/VLAN on the real packets
  $arp  = $pkts | Where-Object { $_ -match '0x0806|ARP' }
  $vlan = $pkts | Where-Object { $_ -match '0x8100|VLAN' }
  [pscustomobject]@{ RealPkts=$pkts.Count; ArpPkts=$arp.Count; VlanTagged=$vlan.Count; Sample=($pkts | Select-Object -First 4) -join "`n" }
}

Write-Host "== Starting capture on node01 (TX) and node02 (RX), filtered to $mac =="
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $startCap -ArgumentList $mac,'TxCap' | Out-Null
Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $startCap -ArgumentList $mac,'RxCap' | Out-Null

Write-Host "== node01 flooding 40 pings to .2 (tagged 711) =="
Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock {
  Remove-NetNeighbor -InterfaceAlias Port3 -IPAddress 192.168.110.2 -Confirm:$false -EA SilentlyContinue
  1..40 | ForEach-Object { Test-Connection -ComputerName 192.168.110.2 -Count 1 -EA SilentlyContinue | Out-Null }
} | Out-Null
Start-Sleep 2

$tx = Invoke-Command azl-node-01.lab.example.com -Credential $ca -Authentication Negotiate -ScriptBlock $stopCount
$rx = Invoke-Command azl-node-02.lab.example.com -Credential $cb -Authentication Negotiate -ScriptBlock $stopCount

Write-Host ""
Write-Host "===== RESULT ====="
Write-Host ("node01 (TX) real packets from its MAC : {0}  (ARP={1}, VLAN-tagged={2})" -f $tx.RealPkts, $tx.ArpPkts, $tx.VlanTagged)
Write-Host ("node02 (RX) real packets from node01  : {0}  (ARP={1}, VLAN-tagged={2})" -f $rx.RealPkts, $rx.ArpPkts, $rx.VlanTagged)
Write-Host ""
Write-Host "node01 TX sample:"; Write-Host $tx.Sample
Write-Host ""
Write-Host "node02 RX sample:"; Write-Host $rx.Sample
