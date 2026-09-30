param([string[]]$Nodes = @('01','02'))
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())
foreach ($n in $Nodes) {
  $short = "azl-node-$n"; $fqdn = "$short.lab.example.com"
  $c = [pscredential]::new("$short\Administrator", $pw)
  $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -ErrorAction SilentlyContinue
  if (-not $s) { Write-Host "$short unreachable" -ForegroundColor Red; continue }
  Write-Host "`n===== $short =====" -ForegroundColor Cyan
  Invoke-Command -Session $s -ScriptBlock {
    $rows = foreach ($a in (Get-NetAdapter | Where-Object { $_.Name -match 'Port3|Port4' })) {
      $ip = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
      if ($ip) {
        $v4 = ($ip | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength) [$($_.PrefixOrigin)/$($_.SuffixOrigin)]" }) -join ', '
      } else {
        $v4 = '(no IPv4)'
      }
      $dhcp = (Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp
      [pscustomobject]@{ Nic = $a.Name; Status = "$($a.Status)"; Speed = $a.LinkSpeed; DHCP = "$dhcp"; IPv4 = $v4 }
    }
    $rows | Format-Table -Auto

    "--- reachable IPv4 neighbors on those NICs ---"
    $idx = (Get-NetAdapter | Where-Object { $_.Name -match 'Port3|Port4' }).ifIndex
    Get-NetNeighbor -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.State -notin 'Unreachable','Incomplete' } |
      Select-Object ifIndex, IPAddress, LinkLayerAddress, State | Format-Table -Auto
  }
  Remove-PSSession $s
}
