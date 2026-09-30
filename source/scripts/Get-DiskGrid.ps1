param([string[]]$Nodes = @('02','03','04','05','06'))
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\azloc-local-admin.cred" -Raw).Trim())
$grid = foreach ($n in $Nodes) {
  $nn = '{0:00}' -f [int]$n
  $short = "azl-node-$nn"; $fqdn = "$short.lab.example.com"
  $c = [pscredential]::new("$short\Administrator", $pw)
  $s = New-PSSession -ComputerName $fqdn -Credential $c -Authentication Negotiate -ErrorAction SilentlyContinue
  if (-not $s) { [pscustomobject]@{ Node=$short; Disk='UNREACHABLE'; Model=''; Role=''; SizeGB=''; Part=''; CanPool=''; Reason='' }; continue }
  $rows = Invoke-Command -Session $s -ScriptBlock {
    $ErrorActionPreference = 'Continue'
    $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue
    Get-Disk | Sort-Object Number | ForEach-Object {
      $d = $_
      $p = $pd | Where-Object { $_.DeviceId -eq $d.Number } | Select-Object -First 1
      $role = if ($d.IsBoot -or $d.IsSystem) { 'BOOT/OS' } else { 'data' }
      [pscustomobject]@{
        Node    = $env:COMPUTERNAME
        Disk    = $d.Number
        Model   = ($d.FriendlyName -replace '\s+NVMe','' -replace '\s+',' ').Trim()
        Role    = $role
        SizeGB  = [math]::Round($d.Size/1GB,0)
        Part    = "$($d.PartitionStyle)"
        CanPool = if ($p) { "$($p.CanPool)" } else { '?' }
        Reason  = if ($p) { "$($p.CannotPoolReason)" } else { '' }
      }
    }
  }
  Remove-PSSession $s
  $rows
}
$grid | Select-Object Node,Disk,Model,Role,SizeGB,Part,CanPool,Reason | Format-Table -Auto

"`n=== DATA-DISK COUNT PER NODE (vs 3-disk standard) ==="
$grid | Where-Object { $_.Role -eq 'data' } | Group-Object Node | ForEach-Object {
  $cnt = $_.Count
  $flag = if ($cnt -eq 3) { 'OK' } else { "SHORT ($cnt of 3)" }
  [pscustomobject]@{ Node=$_.Name; DataDisks=$cnt; Status=$flag }
} | Format-Table -Auto
