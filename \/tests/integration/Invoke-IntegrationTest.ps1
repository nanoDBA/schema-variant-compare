#requires -Version 7.0
#requires -Modules dbatools

[CmdletBinding()]
param(
    [string] $SaPassword = $env:MSSQL_SA_PASSWORD,
    [switch] $KeepContainers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SaPassword)) {
    throw 'Provide -SaPassword or set MSSQL_SA_PASSWORD.'
}

$here = $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $here '../..')
$compareScript = Join-Path $repoRoot 'src/Compare-DatabaseSchema.ps1'
$composeFile = Join-Path $here 'docker-compose.yml'

$env:MSSQL_SA_PASSWORD = $SaPassword
$credential = [PSCredential]::new(
    'sa',
    (ConvertTo-SecureString $SaPassword -AsPlainText -Force)
)

$containersStarted = $false
$sqlConnections = [System.Collections.Generic.List[object]]::new()

function Connect-TestSqlInstance {
    param(
        [Parameter(Mandatory)][string] $Instance,
        [int] $TimeoutSeconds = 180
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = $null

    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $connection = Connect-DbaInstance `
                -SqlInstance $Instance `
                -SqlCredential $credential `
                -TrustServerCertificate `
                -NonPooledConnection `
                -DisableException:$false

            if ($connection) {
                return $connection
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Verbose "Waiting for $Instance: $lastError"
        }

        Start-Sleep -Seconds 3
    }

    throw "SQL Server $Instance did not become ready within $TimeoutSeconds seconds. Last error: $lastError"
}

function Invoke-SeedFile {
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $File
    )

    Invoke-DbaQuery `
        -SqlInstance $Connection `
        -Database master `
        -File $File `
        -EnableException
}

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )

    if (-not $Condition) {
        throw "Integration assertion failed: $Message"
    }
}

try {
    docker compose -f $composeFile up -d --wait

    if ($LASTEXITCODE -ne 0) {
        docker compose -f $composeFile ps
        docker compose -f $composeFile logs --tail 100
        throw "Docker Compose startup failed with exit code $LASTEXITCODE."
    }

    $containersStarted = $true

    $sqlA = Connect-TestSqlInstance -Instance 'localhost,14331'
    $sqlB = Connect-TestSqlInstance -Instance 'localhost,14332'
    $sqlConnections.Add($sqlA)
    $sqlConnections.Add($sqlB)

    Invoke-SeedFile -Connection $sqlA -File (Join-Path $here 'sql/seed-a.sql')
    Invoke-SeedFile -Connection $sqlB -File (Join-Path $here 'sql/seed-b-equivalent.sql')

    $equivalent = & $compareScript `
        -SqlInstance $sqlA,$sqlB `
        -Database SchemaCompareTest

    Assert-Condition `
        -Condition (@($equivalent.VariantSummary).Count -eq 1) `
        -Message 'Equivalent logical schemas should produce one variant.'

    $customerColumns = @(
        $equivalent.Manifest |
            Where-Object {
                $_.SchemaName -eq 'dbo' -and
                $_.ObjectName -eq 'Customer' -and
                $_.ComponentCategory -eq 'COLUMN'
            }
    )

    Assert-Condition `
        -Condition (@($customerColumns | Where-Object DiagnosticOrdinal).Count -gt 0) `
        -Message 'Column ordinals should be retained diagnostically.'

    Invoke-SeedFile -Connection $sqlB -File (Join-Path $here 'sql/apply-drift-b.sql')

    $drifted = & $compareScript `
        -SqlInstance $sqlA,$sqlB `
        -Database SchemaCompareTest

    Assert-Condition `
        -Condition (@($drifted.VariantSummary).Count -eq 2) `
        -Message 'Intentional drift should produce two variants.'

    $differences = @($drifted.VariantDifferences)

    Assert-Condition `
        -Condition ($differences.ComponentCategory -contains 'INDEX') `
        -Message 'Changed index key order should be reported.'

    Assert-Condition `
        -Condition ([bool](
            $differences |
                Where-Object {
                    $_.ComponentCategory -eq 'COLUMN' -and
                    $_.ComponentName -eq 'DisplayName'
                } |
                Select-Object -First 1
        )) `
        -Message 'Changed column length should be reported.'

    Assert-Condition `
        -Condition ($differences.ComponentCategory -contains 'FOREIGN_KEY') `
        -Message 'Changed foreign-key action should be reported.'

    [pscustomobject]@{
        EquivalentVariantCount = @($equivalent.VariantSummary).Count
        DriftedVariantCount    = @($drifted.VariantSummary).Count
        DifferenceCount        = $differences.Count
        PolicyHash             = $drifted.PolicyHash
        Result                 = 'Passed'
    }
}
finally {
    foreach ($connection in $sqlConnections) {
        try {
            $connection.ConnectionContext.Disconnect()
        }
        catch {
            Write-Verbose "Connection cleanup failed: $($_.Exception.Message)"
        }
    }

    if ($containersStarted -and -not $KeepContainers) {
        docker compose -f $composeFile down -v
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Docker cleanup exited with code $LASTEXITCODE."
        }
    }
}
