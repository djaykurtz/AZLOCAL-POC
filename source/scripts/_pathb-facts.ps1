# Path-B staging facts: custom location id, CSV free space, node tooling.
$ErrorActionPreference = 'Continue'
$cl = az customlocation show -g rg-azlocal-poc-001 -n azl-cluster-01-cl --query id -o tsv 2>$null
Write-Host "custom-location: $cl"
$pw = ConvertTo-SecureString ((Get-Content "$PSScriptRoot\..\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)
Invoke-Command azl-node-01.lab.example.com -Credential $cred -Authentication Negotiate -ScriptBlock {
    "--- CSV volumes ---"
    Get-Volume | Where-Object { $_.FileSystem -eq 'CSVFS' } | ForEach-Object {
        "{0}  size={1}GB free={2}GB" -f $_.FileSystemLabel, [math]::Round($_.Size/1GB), [math]::Round($_.SizeRemaining/1GB)
    }
    "--- ClusterStorage dirs ---"
    Get-ChildItem C:\ClusterStorage -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    "--- tools on node ---"
    "qemu-img: " + (Get-Command qemu-img -ErrorAction SilentlyContinue).Source
    "Convert-VHD: " + [bool](Get-Command Convert-VHD -ErrorAction SilentlyContinue)
    "--- node egress to image mirrors ---"
    foreach ($u in 'cloud-images.ubuntu.com','download.cirros-cloud.net') {
        try { $r = Test-NetConnection $u -Port 443 -WarningAction SilentlyContinue; "{0} :443 = {1}" -f $u, $r.TcpTestSucceeded }
        catch { "{0} = err" -f $u }
    }
}
