# Dump Mellanox storage-NIC settings relevant to VLAN tagging / filtering / offload.
# Read-only. ASCII only.
[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-01','azl-node-02'),
  [string]   $Port  = 'Port3',
  [string]   $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw  = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

$blk = {
  param($nic)
  "===== $env:COMPUTERNAME / $nic ====="
  $a = Get-NetAdapter -Name $nic
  "Driver: $($a.DriverProvider) $($a.DriverVersion)  InterfaceDesc: $($a.InterfaceDescription)"
  "--- Advanced properties matching VLAN/Priority/Packet/Encap/Rsc/Offload ---"
  Get-NetAdapterAdvancedProperty -Name $nic -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'VLAN|Priority|Packet|Encap|Qos|Quality|Rsc|Offload|Jumbo|Flow' } |
    Sort-Object DisplayName |
    ForEach-Object { "  {0,-45} = {1}   [{2}]" -f $_.DisplayName, $_.DisplayValue, $_.RegistryKeyword }
  "--- All advanced property keywords (compact) ---"
  (Get-NetAdapterAdvancedProperty -Name $nic -ErrorAction SilentlyContinue | Select-Object -Expand RegistryKeyword | Sort-Object) -join ', '
}

foreach ($n in $Nodes) {
  $cred = [pscredential]::new("$n\Administrator", $pw)
  try {
    Invoke-Command -ComputerName "$n.lab.example.com" -Credential $cred -SessionOption $opt -ScriptBlock $blk -ArgumentList $Port -ErrorAction Stop
    ""
  } catch { "ERR $n : $($_.Exception.Message.Split([char]10)[0])" }
}
