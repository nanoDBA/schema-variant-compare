#requires -Version 7.0
#requires -Modules dbatools

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $SqlInstance,

    [Parameter(Mandatory)]
    [string] $Database,

    [string] $CollectorPath = (Join-Path $PSScriptRoot 'sqlserver/Get-SchemaManifest.sql'),

    [PSCredential] $SqlCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    [Convert]::ToHexString($hash)
}

function Get-ComponentKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Row)

    '{0}|{1}|{2}|{3}|{4}|{5:D10}' -f @(
        $Row.ObjectCategory,
        $Row.SchemaName,
        $Row.ObjectName,
        $Row.ComponentCategory,
        $Row.ComponentName,
        [int]($Row.Ordinal ?? -1)
    )
}

function Get-HashSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Rows,
        [Parameter(Mandatory)] [string] $SourceServer,
        [Parameter(Mandatory)] [string] $SourceDatabase
    )

    $objectHashes = foreach ($objectGroup in $Rows | Group-Object SchemaName, ObjectCategory, ObjectName) {
        $first = $objectGroup.Group[0]
        $signature = $objectGroup.Group |
            Sort-Object { Get-ComponentKey $_ } |
            ForEach-Object { '{0}|{1}' -f (Get-ComponentKey $_), $_.ComponentHash }

        [pscustomobject]@{
            SourceServer   = $SourceServer
            SourceDatabase = $SourceDatabase
            SchemaName     = $first.SchemaName
            ObjectCategory = $first.ObjectCategory
            ObjectName     = $first.ObjectName
            ObjectHash     = Get-Sha256Hex -Text ($signature -join "`n")
            ComponentCount = $objectGroup.Count
        }
    }

    $schemaHashes = foreach ($schemaGroup in $objectHashes | Group-Object SchemaName) {
        $signature = $schemaGroup.Group |
            Sort-Object ObjectCategory, ObjectName |
            ForEach-Object { '{0}|{1}|{2}' -f $_.ObjectCategory, $_.ObjectName, $_.ObjectHash }

        [pscustomobject]@{
            SourceServer   = $SourceServer
            SourceDatabase = $SourceDatabase
            SchemaName     = $schemaGroup.Name
            SchemaHash     = Get-Sha256Hex -Text ($signature -join "`n")
            ObjectCount    = $schemaGroup.Count
        }
    }

    $databaseSignature = $schemaHashes |
        Sort-Object SchemaName |
        ForEach-Object { '{0}|{1}' -f $_.SchemaName, $_.SchemaHash }

    $databaseHash = [pscustomobject]@{
        SourceServer   = $SourceServer
        SourceDatabase = $SourceDatabase
        DatabaseHash   = Get-Sha256Hex -Text ($databaseSignature -join "`n")
        SchemaCount    = @($schemaHashes).Count
        ObjectCount    = @($objectHashes).Count
        ComponentCount = @($Rows).Count
    }

    [pscustomobject]@{
        Objects  = @($objectHashes)
        Schemas  = @($schemaHashes)
        Database = $databaseHash
    }
}

function Compare-ManifestRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]] $Left,
        [Parameter(Mandatory)] [object[]] $Right,
        [Parameter(Mandatory)] [int] $LeftVariant,
        [Parameter(Mandatory)] [int] $RightVariant
    )

    $leftMap = @{}
    foreach ($row in $Left) { $leftMap[(Get-ComponentKey $row)] = $row }

    $rightMap = @{}
    foreach ($row in $Right) { $rightMap[(Get-ComponentKey $row)] = $row }

    $allKeys = @($leftMap.Keys + $rightMap.Keys | Sort-Object -Unique)

    foreach ($key in $allKeys) {
        $leftRow = $leftMap[$key]
        $rightRow = $rightMap[$key]

        $differenceType = if ($null -eq $leftRow) {
            'ExtraInRight'
        }
        elseif ($null -eq $rightRow) {
            'MissingInRight'
        }
        elseif ($leftRow.ComponentHash -ne $rightRow.ComponentHash) {
            'Different'
        }
        else {
            continue
        }

        $row = $leftRow ?? $rightRow
        [pscustomobject]@{
            LeftVariant        = $LeftVariant
            RightVariant       = $RightVariant
            ObjectCategory     = $row.ObjectCategory
            SchemaName         = $row.SchemaName
            ObjectName         = $row.ObjectName
            ComponentCategory  = $row.ComponentCategory
            ComponentName      = $row.ComponentName
            Ordinal            = $row.Ordinal
            DifferenceType     = $differenceType
            LeftDefinition     = if ($null -eq $leftRow) { $null } else { $leftRow.CanonicalDefinition }
            RightDefinition    = if ($null -eq $rightRow) { $null } else { $rightRow.CanonicalDefinition }
            LeftComponentHash  = if ($null -eq $leftRow) { $null } else { $leftRow.ComponentHash }
            RightComponentHash = if ($null -eq $rightRow) { $null } else { $rightRow.ComponentHash }
        }
    }
}

if (-not (Test-Path -LiteralPath $CollectorPath -PathType Leaf)) {
    throw "Collector not found: $CollectorPath"
}

$queryParameters = @{
    Database        = $Database
    File            = $CollectorPath
    EnableException = $true
}
if ($SqlCredential) {
    $queryParameters.SqlCredential = $SqlCredential
}

$manifest = foreach ($instance in $SqlInstance) {
    $rows = Invoke-DbaQuery -SqlInstance $instance @queryParameters

    foreach ($item in $rows) {
        $definition = [string]$item.CanonicalDefinition
        [pscustomobject]@{
            SourceServer        = [string]$instance
            SourceDatabase      = $Database
            ObjectCategory      = [string]$item.ObjectCategory
            SchemaName          = [string]$item.SchemaName
            ObjectName          = [string]$item.ObjectName
            ComponentCategory   = [string]$item.ComponentCategory
            ComponentName       = [string]$item.ComponentName
            Ordinal             = if ($null -eq $item.Ordinal) { $null } else { [int]$item.Ordinal }
            CanonicalDefinition = $definition
            ComponentHash       = Get-Sha256Hex -Text $definition
        }
    }
}

$hashResults = foreach ($serverGroup in $manifest | Group-Object SourceServer) {
    Get-HashSummary `
        -Rows @($serverGroup.Group) `
        -SourceServer $serverGroup.Name `
        -SourceDatabase $Database
}

$databaseSummary = @($hashResults.Database)
$objectSummary = @($hashResults.Objects)
$schemaSummary = @($hashResults.Schemas)

$variantId = 0
$variantSummary = foreach ($hashGroup in $databaseSummary |
    Group-Object DatabaseHash |
    Sort-Object -Property @(
        @{ Expression = 'Count'; Descending = $true },
        @{ Expression = 'Name'; Descending = $false }
    )) {

    $variantId++
    $representative = $hashGroup.Group | Sort-Object SourceServer | Select-Object -First 1

    [pscustomobject]@{
        VariantId            = $variantId
        DatabaseHash         = $hashGroup.Name
        ServerCount          = $hashGroup.Count
        RepresentativeServer = $representative.SourceServer
        Members              = ($hashGroup.Group.SourceServer | Sort-Object) -join ', '
        IsLargestVariant     = $variantId -eq 1
    }
}

$variantDifferences = @()
if (@($variantSummary).Count -gt 1) {
    $anchor = $variantSummary | Sort-Object VariantId | Select-Object -First 1
    $leftRows = @($manifest | Where-Object SourceServer -eq $anchor.RepresentativeServer)

    foreach ($target in $variantSummary | Where-Object VariantId -ne $anchor.VariantId) {
        $rightRows = @($manifest | Where-Object SourceServer -eq $target.RepresentativeServer)
        $variantDifferences += Compare-ManifestRows `
            -Left $leftRows `
            -Right $rightRows `
            -LeftVariant $anchor.VariantId `
            -RightVariant $target.VariantId
    }
}

[pscustomobject]@{
    Manifest           = @($manifest)
    ObjectSummary      = $objectSummary
    SchemaSummary      = $schemaSummary
    DatabaseSummary    = $databaseSummary
    VariantSummary     = @($variantSummary)
    VariantDifferences = @($variantDifferences)
}
