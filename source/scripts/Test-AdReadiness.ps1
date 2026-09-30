# Read-only AD readiness check for Azure Local single-node deploy prep.
# Writes results to out\_ad-readiness.txt so terminal output capture is not an issue.
# ASCII only.
$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path $PSScriptRoot '..\out\_ad-readiness.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Log($m){ $lines.Add($m); Write-Host $m }

function Test-Port($h,$p,$ms=4000){
  $c=[Net.Sockets.TcpClient]::new()
  try{ $a=$c.BeginConnect($h,$p,$null,$null); if($a.AsyncWaitHandle.WaitOne($ms)){ $c.EndConnect($a); $true } else { $false } }
  catch{ $false } finally { $c.Close() }
}

Log ("Run: {0}" -f (Get-Date -Format o))
foreach($d in @('corp.example.com')){
  Log ("REACH {0}: ADWS/9389={1}  LDAP/389={2}  KRB/88={3}" -f $d,(Test-Port $d 9389),(Test-Port $d 389),(Test-Port $d 88))
}

Import-Module ActiveDirectory -ErrorAction SilentlyContinue
foreach($d in @('corp.example.com')){
  try{ $dom=Get-ADDomain -Server $d -ErrorAction Stop; Log ("GET-ADDOMAIN {0}: OK PDC={1} Forest={2}" -f $d,$dom.PDCEmulator,$dom.Forest) }
  catch{ Log ("GET-ADDOMAIN {0}: ERR {1}" -f $d,$_.Exception.Message.Split([char]10)[0]) }
}

$red='OU=Lab-Datacenter,OU=NoSync,OU=Lab,DC=corp,DC=example,DC=com'
try{ $o=Get-ADOrganizationalUnit -Identity $red -Server corp.example.com -ErrorAction Stop; Log ("CORP-OU: EXISTS {0}" -f $o.DistinguishedName) }
catch{ Log ("CORP-OU: ERR {0}" -f $_.Exception.Message.Split([char]10)[0]) }

# Non-destructive write test: -WhatIf create of a throwaway computer object in the OU
try{
  New-ADComputer -Name 'azloc-acl-test' -Path $red -Server corp.example.com -WhatIf -ErrorAction Stop
  Log "CORP-OU-WRITE: -WhatIf create SUCCEEDED (path resolvable; real ACL proven only on actual create)"
}catch{ Log ("CORP-OU-WRITE: ERR {0}" -f $_.Exception.Message.Split([char]10)[0]) }

# NA candidate OUs
try{
  $na=Get-ADOrganizationalUnit -Server corp.example.com -Filter 'Name -like "*Lab*" -or Name -like "*DataCenter*"' -ResultSetSize 12 -ErrorAction Stop
  if($na){ foreach($x in $na){ Log ("NA-CANDIDATE: {0}" -f $x.DistinguishedName) } } else { Log "NA-CANDIDATE: none matched Lab/DataCenter" }
}catch{ Log ("NA-SEARCH: ERR {0}" -f $_.Exception.Message.Split([char]10)[0]) }

# Forest trust view from the corporate forest
try{
  $t=Get-ADTrust -Filter * -Server corp.example.com -ErrorAction Stop | Where-Object { $_.Name -like '*corp*' }
  if($t){ foreach($x in $t){ Log ("TRUST: {0} Dir={1} Type={2} ForestTransitive={3}" -f $x.Name,$x.Direction,$x.TrustType,$x.ForestTransitive) } } else { Log "TRUST: no corp trust row returned" }
}catch{ Log ("TRUST: ERR {0}" -f $_.Exception.Message.Split([char]10)[0]) }

Set-Content -Path $out -Value $lines -Encoding utf8
Write-Host "`nWROTE $out"
