# Revert Port3 on node01 + node02 to clean baseline after manual tagging tests.
# Removes physical VlanID (back to 0/untagged) and the 192.168.110.x test IPs.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
foreach ($n in 'azl-node-01','azl-node-02') {
  $c = [pscredential]::new("$n\Administrator",$pw)
  Write-Host "==== Reverting $n Port3 to baseline ===="
  $r = Invoke-Command -ComputerName "$n.lab.example.com" -Credential $c -Authentication Negotiate -ScriptBlock {
    # remove test IPs
    Get-NetIPAddress -InterfaceAlias Port3 -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -like '192.168.110.*' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    # clear physical VLAN tag back to 0 (untagged / standalone default)
    try { Set-NetAdapterAdvancedProperty -Name Port3 -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction Stop } catch {}
    # stop any leftover pktmon + clean temp captures
    pktmon stop 2>&1 | Out-Null
    pktmon filter remove 2>&1 | Out-Null
    Remove-Item C:\Windows\Temp\rx711.etl,C:\Windows\Temp\rx711.txt,C:\Windows\Temp\dual.etl,C:\Windows\Temp\dual.txt -ErrorAction SilentlyContinue
    Start-Sleep 2
    $vlan = (Get-NetAdapterAdvancedProperty -Name Port3 -RegistryKeyword 'VlanID' -ErrorAction SilentlyContinue).RegistryValue
    $ips  = (Get-NetIPAddress -InterfaceAlias Port3 -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress -join ','
    [pscustomobject]@{ Node=$env:COMPUTERNAME; VlanIDnow=$vlan; IPsNow=$ips; Status=(Get-NetAdapter -Name Port3).Status }
  }
  $r | Format-List
}
Write-Host "Baseline restore complete. Port3 should show VlanID {0} and only 169.254.x link-local (or empty)."
