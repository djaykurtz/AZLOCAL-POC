# Reveal-all-MACs helper: forces every storage port on all 4 nodes to TRANSMIT so the switches
# learn each MAC on its real port. Run this RIGHT AFTER the network operator untags the storage ports, then have
# him immediately dump `show mac address-table` on SW1 and SW2 (MACs age out ~5 min on Arista).
# Method: set each port untagged (VlanID 0), give it a temp IP, ping an unused in-subnet address to
# emit ARP broadcasts out that port. Read-only to the switch; reversible on the hosts (cleanup at end).
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$nodes = @(
  @{ sam='azl-node-01'; base=11 }
  @{ sam='azl-node-02'; base=21 }
  @{ sam='azl-node-04'; base=41 }
  @{ sam='azl-node-06'; base=61 }
)
$gen = {
  param($base)
  $out = @()
  $i = 0
  foreach ($p in 'Port3','Port4') {
    $ip = "192.168.200.$($base + $i)"
    Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.200.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
    New-NetIPAddress -InterfaceAlias $p -IPAddress $ip -PrefixLength 24 -EA SilentlyContinue | Out-Null
    # ping an unused address to force ARP broadcast egress out this port
    Test-Connection -ComputerName '192.168.200.254' -Count 3 -EA SilentlyContinue | Out-Null
    $mac = (Get-NetAdapter -Name $p).MacAddress
    $out += [pscustomobject]@{ Node=$env:COMPUTERNAME; NIC=$p; TempIP=$ip; MAC=$mac }
    $i++
  }
  $out
}
Write-Host "Generating ARP traffic on all storage ports (untagged) so switches learn every MAC..."
$rows = foreach ($nd in $nodes) {
  $cred = [pscredential]::new("$($nd.sam)\Administrator",$pw)
  try { Invoke-Command "$($nd.sam).lab.example.com" -Credential $cred -Authentication Negotiate -ScriptBlock $gen -ArgumentList $nd.base }
  catch { [pscustomobject]@{ Node=$nd.sam; NIC='(unreachable)'; TempIP=''; MAC="$($_.Exception.Message)" } }
}
$rows | Format-Table Node,NIC,TempIP,MAC -AutoSize
Write-Host ""
Write-Host ">>> NOW have the network operator run 'show mac address-table' on SW1 and SW2 (within ~5 min) <<<"
Write-Host "Match these MACs (Arista fmt):"
Write-Host "  node01 P3 0000.5e00.5301  P4 0000.5e00.5306"
Write-Host "  node02 P3 0000.5e00.5303  P4 0000.5e00.5304"
Write-Host "  node04 P3 0000.5e00.5307  P4 0000.5e00.5308"
Write-Host "  node06 P3 0000.5e00.5309  P4 0000.5e00.530a"
Write-Host ""
Write-Host "Run scripts/_reveal-macs-cleanup.ps1 when done to remove the temp IPs."
