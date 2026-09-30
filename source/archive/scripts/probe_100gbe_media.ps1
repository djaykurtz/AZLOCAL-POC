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
      # MediaConnectionState is the true carrier signal; ConnectorPresent = transceiver/cable seated
      $mcs = $a.MediaConnectionState
      $conn = $a.ConnectorPresent
      # Pull link/module detail from the NIC's WMI class where available
      [pscustomobject]@{
        Nic          = $a.Name
        AdminStatus  = "$($a.Status)"           # 'Up' can be admin-up even w/o carrier on some drivers
        MediaConn    = "$mcs"                    # Connected / Disconnected = the REAL signal
        Connector    = "$conn"                   # True = transceiver/DAC physically seated
        Speed        = $a.LinkSpeed
        FullDuplex   = $a.FullDuplex
      }
    }
    $rows | Format-Table -Auto

    "--- driver-reported detail (inbox driver, limited) ---"
    foreach ($a in (Get-NetAdapter | Where-Object { $_.Name -match 'Port3|Port4' })) {
      $hw = Get-NetAdapterHardwareInfo -Name $a.Name -ErrorAction SilentlyContinue
      "$($a.Name): PCIe slot=$($hw.Slot) bus=$($hw.Bus) | ifOperStatus via WMI:"
      Get-CimInstance -ClassName MSFT_NetAdapter -Namespace root/StandardCimv2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $a.Name } |
        Select-Object Name, MediaConnectState, ConnectorPresent, InterfaceOperationalStatus |
        Format-List
    }
  }
  Remove-PSSession $s
}
