# Path-B stage 2: copy the VHDX to a cluster CSV, then create the Arc VM gallery image.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vhdx = Join-Path $root 'out\img\cirros.vhdx'
if (-not (Test-Path $vhdx)) { throw "Run _pathb-stage-image.ps1 first; $vhdx missing" }

$rg = 'rg-azlocal-poc-001'
$clName = 'azl-cluster-01-cl'
$clId = az customlocation show -g $rg -n $clName --query id -o tsv
$loc  = az customlocation show -g $rg -n $clName --query location -o tsv
Write-Host "custom-location: $clId"
Write-Host "location: $loc"

$csvDir  = 'C:\ClusterStorage\UserStorage_1\images'
$csvPath = "$csvDir\cirros.vhdx"

$pw = ConvertTo-SecureString ((Get-Content "$root\.creds\sim-example-internal-admin.cred" -Raw).Trim())
$cred = [pscredential]::new('sim\labadmin', $pw)
$s = New-PSSession azl-node-01.lab.example.com -Credential $cred -Authentication Negotiate
try {
    Invoke-Command -Session $s -ScriptBlock { param($d) New-Item -ItemType Directory -Force -Path $d | Out-Null } -ArgumentList $csvDir
    $exists = Invoke-Command -Session $s -ScriptBlock { param($p) Test-Path $p } -ArgumentList $csvPath
    if (-not $exists) {
        Write-Host "Copying VHDX to $csvPath ..."
        Copy-Item -Path $vhdx -Destination $csvPath -ToSession $s -Force
    } else {
        Write-Host "VHDX already present at $csvPath"
    }
    $sz = Invoke-Command -Session $s -ScriptBlock { param($p) [math]::Round((Get-Item $p).Length/1MB,1) } -ArgumentList $csvPath
    Write-Host "on-CSV size: $sz MB"
} finally {
    Remove-PSSession $s
}

Write-Host "Creating gallery image cirros-064 ..."
az stack-hci-vm image create `
    --resource-group $rg `
    --custom-location $clId `
    --location $loc `
    --name 'cirros-064' `
    --os-type 'Linux' `
    --image-path $csvPath `
    2>&1 | Tee-Object -FilePath "$root\out\_image-create-cirros.txt"

Write-Host "--- image list ---"
az stack-hci-vm image list -g $rg --query "[].{name:name,prov:properties.provisioningState}" -o table
