[CmdletBinding()]
param(
    [int[]]$Nodes = @(1,2,4,5,6),
    [string]$CredPath = '.\.creds\azloc-local-admin.cred'
)
$pw = ConvertTo-SecureString ((Get-Content $CredPath -Raw).Trim())
$rows = foreach ($n in $Nodes) {
    $nn = '{0:00}' -f $n
    $short = "azl-node-$nn"
    $c = [pscredential]::new("$short\Administrator", $pw)
    $o = New-PSSessionOption -OpenTimeout 8000 -OperationTimeout 60000
    try {
        $s = New-PSSession -ComputerName "$short.lab.example.com" -Credential $c -Authentication Negotiate -SessionOption $o -ErrorAction Stop
    } catch {
        [pscustomobject]@{ Node=$short; BIOS='UNREACHABLE'; NVMeCtrl=''; PhysDisks=''; Poolable='' }
        continue
    }
    $r = Invoke-Command -Session $s -ScriptBlock {
        $b = Get-CimInstance Win32_BIOS
        $ctrl = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVMe Controller|Standard NVM Express' })
        $pd = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Node      = $env:COMPUTERNAME
            BIOS      = $b.SMBIOSBIOSVersion
            NVMeCtrl  = $ctrl.Count
            PhysDisks = $pd.Count
            Poolable  = @($pd | Where-Object CanPool).Count
        }
    }
    Remove-PSSession $s
    $r
}
$rows | Format-Table Node, BIOS, NVMeCtrl, PhysDisks, Poolable -AutoSize
