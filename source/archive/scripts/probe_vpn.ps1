function Probe-Tcp {
    param([string]$Target, [int]$Port, [int]$TimeoutMs = 2500)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($Target, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $c.Connected) {
            $c.EndConnect($iar); $c.Close(); return 'open'
        }
        $c.Close(); return 'closed/filtered'
    }
    catch { return 'error' }
}

$rows = New-Object System.Collections.Generic.List[object]

# Sanity: fake port must NOT be 'open' on an honest VPN
$rows.Add([pscustomobject]@{ target = 'azl-node-01.lab.example.com'; port = 12345; result = (Probe-Tcp 'azl-node-01.lab.example.com' 12345); note = 'SANITY fake-port' })

# KVM
$rows.Add([pscustomobject]@{ target = 'kvm-01.lab.example.com'; port = 443; result = (Probe-Tcp 'kvm-01.lab.example.com' 443); note = 'KVM' })

# iDRAC :443 per node (primary acceptance criterion)
foreach ($n in 1..6) {
    $idrac = "azl-node-0${n}adm.lab.example.com"
    $rows.Add([pscustomobject]@{ target = $idrac; port = 443; result = (Probe-Tcp $idrac 443); note = 'iDRAC web' })
}

# OS plane (secondary - nodes likely not imaged yet so 'closed' is expected)
foreach ($n in 1..6) {
    $fqdn = "azl-node-0$n.lab.example.com"
    $rows.Add([pscustomobject]@{ target = $fqdn; port = 5985; result = (Probe-Tcp $fqdn 5985); note = 'OS WinRM' })
}

$rows | Format-Table -AutoSize | Out-String -Width 200
