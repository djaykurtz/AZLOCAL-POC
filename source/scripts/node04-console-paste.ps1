if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ Write-Host 'NOT ELEVATED - WinRM setup will FAIL (Access denied). Open admin PowerShell: Task Mgr > Run new task > powershell > check admin. Aborting.' -ForegroundColor Red; return }
$name='AZL-NODE-04'; $ip='10.10.1.190'; $pfx=22; $gw='10.10.1.1'; $dns=@('10.20.50.50','10.20.10.50'); $suffix='lab.example.com'
$a = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -EA SilentlyContinue | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
Remove-NetRoute -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Confirm:$false -EA SilentlyContinue
Set-NetIPInterface -InterfaceIndex $a.ifIndex -Dhcp Disabled
New-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $ip -PrefixLength $pfx -DefaultGateway $gw
Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $dns
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Domain' -Value $suffix
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'NV Domain' -Value $suffix
Set-TimeZone -Id 'Pacific Standard Time'
Set-Service WinRM -StartupType Automatic; Start-Service WinRM
winrm quickconfig -quiet -force 2>$null
Enable-PSRemoting -Force -SkipNetworkProfileCheck
try { Set-Item WSMan:\localhost\Service\AllowUnencrypted $true -Force -EA Stop } catch { Write-Host 'AllowUnencrypted skipped (not needed - Negotiate encrypts)' -ForegroundColor DarkGray }
Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management' -EA SilentlyContinue
Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -RemoteAddress Any -EA SilentlyContinue
Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP' -RemoteAddress Any -EA SilentlyContinue
Enable-NetFirewallRule -Name 'FPS-ICMP4-ERQ-In' -EA SilentlyContinue
New-NetFirewallRule -DisplayName 'Azure Local OS Mgmt 30301' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 30301 -Profile Any -Enabled True -EA SilentlyContinue
winrm enumerate winrm/config/listener
Test-Connection $gw -Count 2
Rename-Computer -NewName $name -Force
Write-Host "Renamed to $name and network configured. REBOOT now to apply the rename: Restart-Computer -Force" -ForegroundColor Yellow
