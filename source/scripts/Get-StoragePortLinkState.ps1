[CmdletBinding()]
param(
  [string[]] $Nodes = @('azl-node-01','azl-node-02','azl-node-04','azl-node-06'),
  [string]   $CredPath = '.\.creds\azloc-local-admin.cred'
)
$ErrorActionPreference = 'Stop'
$pw  = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 120000

$rows = foreach ($n in $Nodes) {
  $cred = [pscredential]::new("$n\Administrator", $pw)
  try {
    Invoke-Command -ComputerName "$n.lab.example.com" -Credential $cred -SessionOption $opt -ScriptBlock {
      Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*Mellanox*' } |
        Select-Object @{n='Node';e={$env:COMPUTERNAME}}, Name,
          @{n='MAC';e={$_.MacAddress}}, Status, LinkSpeed, MediaConnectionState
    } -ErrorAction Stop
  } catch {
    [pscustomobject]@{ Node=$n; Name='ERR'; MAC=''; Status=$_.Exception.Message; LinkSpeed=''; MediaConnectionState='' }
  }
}

$rows | Select-Object Node, Name, MAC, Status, LinkSpeed, MediaConnectionState |
  Sort-Object Node, Name | Format-Table -Auto | Out-String | Write-Output
