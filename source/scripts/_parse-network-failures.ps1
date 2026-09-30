# Regex-parse network failures (avoids embedded-JSON brace walking issues)
$ds = Get-Content .\out\_ds-fresh.json -Raw | ConvertFrom-Json
$err = $ds.properties.reportedProperties.validationStatus.steps | Where-Object status -eq 'Error' | Select-Object -First 1
$excText = ($err.exception -join "`n")

# Save raw exception to a file for inspection
$rawFile = "out\_net-exception-raw.txt"
$excText | Set-Content $rawFile -Encoding UTF8
Write-Host "Raw exception written to $rawFile ($($excText.Length) bytes)"
Write-Host ""

# Grab each Name/Detail pair with regex
$matches = [regex]::Matches($excText, '(?s)"Name":\s*"([^"]+)".*?"Detail":\s*"([^"]+(?:\\.[^"]*)*)".*?"Source":\s*"([^"]+)"')
Write-Host "Regex matches: $($matches.Count)"
Write-Host ""

$rows = foreach ($m in $matches) {
    [pscustomobject]@{
        Check  = $m.Groups[1].Value
        Source = $m.Groups[3].Value
        Detail = $m.Groups[2].Value -replace '\\n',"`n  " -replace '\\"','"'
    }
}

Write-Host "==== Grouped by check name ===="
$rows | Group-Object Check | Sort-Object Count -Descending | ForEach-Object {
    Write-Host ""
    Write-Host "Count=$($_.Count)  Check=$($_.Name)"
    Write-Host "  Affected: $(($_.Group.Source | Sort-Object -Unique) -join ', ')"
    $exampleDetail = ($_.Group[0].Detail -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -First 3) -join "`n    "
    Write-Host "  Detail sample:`n    $exampleDetail"
}
