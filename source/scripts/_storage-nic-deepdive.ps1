# Comprehensive storage-NIC deep dive on node01 + node02 Port3, saved for the writeup.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$out = ".\out\_storage-nic-deepdive.txt"
"STORAGE NIC DEEP DIVE  $(Get-Date -Format u)" | Set-Content $out

foreach ($n in 'azl-node-01','azl-node-02') {
  $c = [pscredential]::new("$n\Administrator",$pw)
  "`n=====================================================================" | Add-Content $out
  "==== $n  Port3 ====" | Add-Content $out
  "=====================================================================" | Add-Content $out
  $data = Invoke-Command -ComputerName "$n.lab.example.com" -Credential $c -Authentication Negotiate -ScriptBlock {
    $sb = New-Object System.Text.StringBuilder
    function A($t){ [void]$sb.AppendLine("`n--- $t ---") }
    A "Get-NetAdapter Port3"
    [void]$sb.AppendLine((Get-NetAdapter -Name Port3 | Format-List Name,InterfaceDescription,DriverProvider,DriverVersion,DriverFileName,MacAddress,MtuSize,LinkSpeed,MediaConnectionState | Out-String))
    A "Advanced properties (VLAN / VMQ / RSS / Jumbo / RDMA / QoS)"
    [void]$sb.AppendLine((Get-NetAdapterAdvancedProperty -Name Port3 | Select-Object DisplayName,DisplayValue,RegistryKeyword,RegistryValue | Format-Table -AutoSize | Out-String -Width 200))
    A "Get-NetAdapterRdma"
    [void]$sb.AppendLine((Get-NetAdapterRdma -Name Port3 -ErrorAction SilentlyContinue | Format-List Name,Enabled,OperationalState,MaxQueuePairCount | Out-String))
    A "Get-NetAdapterQos (DCB/PFC/ETS)"
    [void]$sb.AppendLine((Get-NetAdapterQos -Name Port3 -ErrorAction SilentlyContinue | Out-String))
    A "Get-NetAdapterVmq"
    [void]$sb.AppendLine((Get-NetAdapterVmq -Name Port3 -ErrorAction SilentlyContinue | Format-List | Out-String))
    A "Get-NetAdapterStatistics (incl RX/TX discards)"
    [void]$sb.AppendLine((Get-NetAdapterStatistics -Name Port3 | Format-List * | Out-String))
    A "Mellanox WinOF-2 perf counters (VLAN / discard / priority if present)"
    try {
      $sets = (Get-Counter -ListSet 'Mellanox*' -ErrorAction SilentlyContinue).CounterSetName
      [void]$sb.AppendLine("Counter sets: " + ($sets -join '; '))
    } catch { [void]$sb.AppendLine("no Mellanox perf counter sets") }
    $sb.ToString()
  }
  $data | Add-Content $out
}
Write-Host "Saved deep dive to $out"
Write-Host ""
Get-Content $out
