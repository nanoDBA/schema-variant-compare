#requires -Version 7.0
#requires -Modules dbatools

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $SqlInstance,

    [Parameter(Mandatory)]
    [string] $Database,

    [string] $CollectorPath = (Join-Path $PSScriptRoot 'sqlserver/Get-SchemaManifest.sql')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash)
}

function Get-CanonicalSortKey {
    param([Parameter(Mandatory)] $Row)

    '{0}|{1}|{2}|{3}|{4}|{5:D10}' -f \
        $Row.ObjectCategory,
        $Row.SchemaName,
        $Row.ObjectName,
        $Row.ComponentCategory,
        $Row.ComponentName,
        [int]($Row.Ordinal ?? -1)
}

$manifest = foreach ($instance in $SqlInstance) {
    Invoke-DbaQuery \
        -SqlInstance $instance \
        -Database $Database \
        -File $CollectorPath \
        -EnableException |
        ForEach-Object {
            [pscustomobject]@{
                SourceServer        = [string]$instance
                SourceDatabase      = $Database
                ObjectCategory      = [string]$_.ObjectCategory
                SchemaName          = [string]$_.SchemaName
                ObjectName          = [string]$_.ObjectName
                ComponentCategory   = [string]$_.ComponentCategory
                ComponentName       = [string]$_.ComponentName
                Ordinal             = if ($null -eq $_.Ordinal) { $null } else { [int]$_.Ordinal }
                CanonicalDefinition = [string]$_.CanonicalDefinition
                ComponentHash       = Get-Sha256Hex -Text ([string]$_.CanonicalDefinition)
            }
        }
}

$databaseSummaries = foreach ($serverGroup in $manifest | Group-Object SourceServer) {
    $signature = $serverGroup.Group |
        Sort-Object { Get-CanonicalSortKey $_ } |
        ForEach-Object {
            '{0}|{1}' -f (Get-CanonicalSortKey $_), $_.ComponentHash
        }

    [pscustomobject]@{
        SourceServer   = $serverGroup.Name
        SourceDatabase = $Database
        DatabaseHash   = Get-Sha256Hex -Text ($signature -join "`n")
        ComponentCount = $serverGroup.Count
    }
}

$variantId = 0
$variantSummary = foreach ($hashGroup in $databaseSummaries |
    Group-Object DatabaseHash |
    Sort-Object Count -Descending, Name) {

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

[pscustomobject]@{
    Manifest        = $manifest
    DatabaseSummary = $databaseSummaries
    VariantSummary  = $variantSummary
}
