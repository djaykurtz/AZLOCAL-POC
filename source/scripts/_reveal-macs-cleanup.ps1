# Cleanup for _reveal-macs.ps1: removes the temp 192.168.200.x IPs from all storage ports,
# leaves VlanID 0 baseline on all 4 nodes.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$results = foreach ($sam in 'azl-node-01','azl-node-02','azl-node-04','azl-node-06') {
  $cred = [pscredential]::new("$sam\Administrator",$pw)
  try {
    Invoke-Command "$sam.lab.example.com" -Credential $cred -Authentication Negotiate -ScriptBlock {
      foreach ($p in 'Port3','Port4') {
        Get-NetIPAddress -InterfaceAlias $p -AddressFamily IPv4 -EA SilentlyContinue | Where-Object {$_.IPAddress -like '192.168.200.*'} | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $p -RegistryKeyword 'VlanID' -RegistryValue 0 -ErrorAction SilentlyContinue
      }
      $v3 = (Get-NetAdapterAdvancedProperty -Name Port3 -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
      $v4 = (Get-NetAdapterAdvancedProperty -Name Port4 -RegistryKeyword 'VlanID' -EA SilentlyContinue).RegistryValue
      [pscustomobject]@{ Node=$env:COMPUTERNAME; Port3Vlan=$v3; Port4Vlan=$v4 }
    }
  } catch { [pscustomobject]@{ Node=$sam; Port3Vlan='ERR'; Port4Vlan="$($_.Exception.Message)" } }
}
$results | Format-Table -AutoSize
Write-Host "Cleanup complete. All storage ports should show VlanID 0 and no 192.168.200.x IPs."
