# ===== node02 console bring-up - PASTE INTO KVM (local PowerShell on the node) =====
# Static IP, no DHCP. Enables WinRM so the DevBox can take over after this.
# Values match the POC plan: node02 = 10.10.1.188/22, gw .1, DNS .50/.50
$ip='10.10.1.188'; $pfx=22; $gw='10.10.1.1'; $dns=@('10.20.50.50','10.20.10.50')
$suffix='lab.example.com'

# 1) Pick the management NIC (first one with link 'Up')
$a = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $a) { Write-Host 'NO UP ADAPTER - check cabling' -ForegroundColor Red; return }
Write-Host "Using NIC: $($a.Name)  $($a.InterfaceDescription)" -ForegroundColor Cyan

# 2) Static IPv4 (wipe DHCP/old, disable DHCP, set new)
Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -EA SilentlyContinue | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
Remove-NetRoute -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Confirm:$false -EA SilentlyContinue
Set-NetIPInterface -InterfaceIndex $a.ifIndex -Dhcp Disabled
New-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $ip -PrefixLength $pfx -DefaultGateway $gw | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $dns

# 3) DNS suffix
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain' -Value $suffix
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value $suffix

# 4) Time zone (lab = Portland)
Set-TimeZone -Id 'Pacific Standard Time'

# 5) WinRM on + firewall (so DevBox can reach it; workgroup => allow unencrypted Negotiate)
Set-Service WinRM -StartupType Automatic; Start-Service WinRM
winrm quickconfig -quiet -force 2>$null
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Set-Item WSMan:\localhost\Service\AllowUnencrypted $true -Force
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -EA SilentlyContinue
New-NetFirewallRule -DisplayName 'Azure Local OS Mgmt 30301' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 30301 -Profile Any -Enabled True -EA SilentlyContinue | Out-Null

# 6) Report
Write-Host "`n--- node02 result ---" -ForegroundColor Green
Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Format-Table IPAddress,PrefixLength,PrefixOrigin -Auto
Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Format-Table InterfaceAlias,ServerAddresses -Auto
"WinRM: $((Get-Service WinRM).Status)  hostname: $env:COMPUTERNAME"
Write-Host "From DevBox now:  Test-WSMan -ComputerName $ip -Authentication Negotiate -Credential (Get-Credential azl-node-02\Administrator)" -ForegroundColor Yellow
# ===== end paste =====
