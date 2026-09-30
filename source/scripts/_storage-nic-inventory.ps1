# Host-side storage-NIC inventory for ALL nodes: authoritative adapter NAME <-> MAC map.
# This is the labeled key to cross-reference against the switch MAC tables (SW1/SW2 et9-et14)
# so we can build the definitive per-node  adapter -> switch -> switch-port -> VLAN  mapping
# with ZERO assumptions. Read-only.
$pw = ConvertTo-SecureString ((Get-Content ".\.creds\azloc-local-admin.cred" -Raw).Trim())
$nodes = @(
  @{ n='AZL-NODE-01'; sam='azl-node-01' }
  @{ n='AZL-NODE-02'; sam='azl-node-02' }
  @{ n='AZL-NODE-04'; sam='azl-node-04' }
  @{ n='AZL-NODE-06'; sam='azl-node-06' }
)
$rows = foreach ($nd in $nodes) {
  $cred = [pscredential]::new("$($nd.sam)\Administrator",$pw)
  try {
    Invoke-Command "$($nd.sam).lab.example.com" -Credential $cred -Authentication Negotiate -ScriptBlock {
      Get-NetAdapter -Name Port3,Port4 -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
          Node   = $env:COMPUTERNAME
          Adapter= $_.Name
          MAC    = $_.MacAddress
          MAC_lc = ($_.MacAddress -replace '-','').ToLower()  # switch-table format 9803.9bxx.xxxx style base
          Status = $_.Status
          Media  = $_.MediaConnectionState
          Speed  = $_.LinkSpeed
          Desc   = $_.InterfaceDescription
        }
      }
    }
  } catch {
    [pscustomobject]@{ Node=$nd.n; Adapter='(unreachable)'; MAC=''; MAC_lc=''; Status="$($_.Exception.Message)"; Media=''; Speed=''; Desc='' }
  }
}
$rows | Sort-Object Node,Adapter | Format-Table Node,Adapter,MAC,Status,Media,Speed -AutoSize
$rows | Sort-Object Node,Adapter | Select-Object Node,Adapter,MAC,MAC_lc,Status,Media,Speed,Desc |
  Export-Csv .\out\_storage-nic-inventory.csv -NoTypeInformation
Write-Host ""
Write-Host "Saved: out\_storage-nic-inventory.csv"
Write-Host "Switch-table MAC format reminder: Arista shows e.g. 0000.5e00.5306 for 00-00-5E-00-53-06."
