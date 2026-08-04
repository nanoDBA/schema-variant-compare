#requires -Version 7.0
#requires -Modules dbatools

[CmdletBinding()]
param(
    [Parameter(Mandatory)][object[]] $SqlInstance,
    [Parameter(Mandatory)][string] $Database,
    [string] $CollectorPath = (Join-Path $PSScriptRoot 'sqlserver/Get-SchemaManifest.sql'),
    [PSCredential] $SqlCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$CollectorVersion = '0.3.0'
$ManifestFormatVersion = '2'
$CanonicalizationVersion = '2'

$ComparisonPolicy = [ordered]@{
    TableColumnOrder          = 'Ignore'
    IndexKeyColumnOrder       = 'Strict'
    IndexIncludeColumnOrder   = 'Ignore'
    ConstraintColumnOrder     = 'Strict'
    ExplicitConstraintNames   = 'Compare'
    SystemConstraintNames     = 'Ignore'
    DisabledIndexes           = 'Compare'
    IndexStorageProperties    = 'Ignore'
    XmlIndexes                = 'IgnoreWithVerboseWarning'
    SpatialIndexes            = 'IgnoreWithVerboseWarning'
    FullTextIndexes           = 'IgnoreWithVerboseWarning'
    TemporalAttributes        = 'IgnoreWithVerboseWarning'
    MemoryOptimizedAttributes = 'IgnoreWithVerboseWarning'
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($Text)
        )
    )
}

function Get-PolicyHash {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Policy)
    $signature = $Policy.GetEnumerator() |
        Sort-Object Key |
        ForEach-Object { '{0}={1}' -f $_.Key,$_.Value }
    Get-Sha256Hex -Text ($signature -join "`n")
}

function Test-DbNull {
    param($Value)

    return (
        $null -eq $Value -or
        $Value -is [System.DBNull]
    )
}

function Get-ComponentKey {
    param([Parameter(Mandatory)] $Row)

    $ordinal = if (Test-DbNull $Row.Ordinal) {
        -1
    }
    else {
        [int]$Row.Ordinal
    }

    '{0}|{1}|{2}|{3}|{4}|{5:D10}' -f @(
        $Row.ObjectCategory,
        $Row.SchemaName,
        $Row.ObjectName,
        $Row.ComponentCategory,
        $Row.ComponentName,
        $ordinal
    )
}

function Get-HashSummary {
    param(
        [Parameter(Mandatory)][object[]] $Rows,
        [Parameter(Mandatory)][string] $SourceServer,
        [Parameter(Mandatory)][string] $SourceDatabase,
        [Parameter(Mandatory)][string] $PolicyHash
    )

    $objects = foreach ($g in $Rows | Group-Object SchemaName,ObjectCategory,ObjectName) {
        $first = $g.Group[0]
        $sig = $g.Group | Sort-Object { Get-ComponentKey $_ } |
            ForEach-Object { '{0}|{1}' -f (Get-ComponentKey $_),$_.ComponentHash }
        [pscustomobject]@{
            SourceServer=$SourceServer; SourceDatabase=$SourceDatabase
            SchemaName=$first.SchemaName; ObjectCategory=$first.ObjectCategory
            ObjectName=$first.ObjectName; ObjectHash=Get-Sha256Hex ($sig -join "`n")
            ComponentCount=$g.Count; ComparisonPolicyHash=$PolicyHash
            ManifestFormatVersion=$ManifestFormatVersion
            CanonicalizationVersion=$CanonicalizationVersion
        }
    }

    $schemas = foreach ($g in $objects | Group-Object SchemaName) {
        $sig = $g.Group | Sort-Object ObjectCategory,ObjectName |
            ForEach-Object { '{0}|{1}|{2}' -f $_.ObjectCategory,$_.ObjectName,$_.ObjectHash }
        [pscustomobject]@{
            SourceServer=$SourceServer; SourceDatabase=$SourceDatabase
            SchemaName=$g.Name; SchemaHash=Get-Sha256Hex ($sig -join "`n")
            ObjectCount=$g.Count; ComparisonPolicyHash=$PolicyHash
            ManifestFormatVersion=$ManifestFormatVersion
            CanonicalizationVersion=$CanonicalizationVersion
        }
    }

    $dbSig = @(
        "policy=$PolicyHash"
        "manifest_format=$ManifestFormatVersion"
        "canonicalization=$CanonicalizationVersion"
        $schemas | Sort-Object SchemaName | ForEach-Object { '{0}|{1}' -f $_.SchemaName,$_.SchemaHash }
    )

    [pscustomobject]@{
        Objects=@($objects)
        Schemas=@($schemas)
        Database=[pscustomobject]@{
            SourceServer=$SourceServer; SourceDatabase=$SourceDatabase
            DatabaseHash=Get-Sha256Hex ($dbSig -join "`n")
            SchemaCount=@($schemas).Count; ObjectCount=@($objects).Count
            ComponentCount=@($Rows).Count; ComparisonPolicyHash=$PolicyHash
            ManifestFormatVersion=$ManifestFormatVersion
            CanonicalizationVersion=$CanonicalizationVersion
            CollectorVersion=$CollectorVersion
        }
    }
}

function Compare-ManifestRows {
    param(
        [Parameter(Mandatory)][object[]] $Left,
        [Parameter(Mandatory)][object[]] $Right,
        [Parameter(Mandatory)][int] $LeftVariant,
        [Parameter(Mandatory)][int] $RightVariant
    )

    $lm=@{}; foreach($r in $Left){$lm[(Get-ComponentKey $r)]=$r}
    $rm=@{}; foreach($r in $Right){$rm[(Get-ComponentKey $r)]=$r}

    foreach($key in @($lm.Keys+$rm.Keys|Sort-Object -Unique)){
        $l=$lm[$key]; $r=$rm[$key]
        $type = if($null -eq $l){'ExtraInRight'}
                elseif($null -eq $r){'MissingInRight'}
                elseif($l.ComponentHash -ne $r.ComponentHash){'Different'}
                else{continue}
        $row=$l ?? $r
        [pscustomobject]@{
            LeftVariant=$LeftVariant; RightVariant=$RightVariant
            ObjectCategory=$row.ObjectCategory; SchemaName=$row.SchemaName
            ObjectName=$row.ObjectName; ComponentCategory=$row.ComponentCategory
            ComponentName=$row.ComponentName; Ordinal=$row.Ordinal
            DifferenceType=$type
            LeftRawDefinition = if ($null -eq $l) { $null } else { $l.RawDefinition }
            RightRawDefinition = if ($null -eq $r) { $null } else { $r.RawDefinition }
            LeftDefinition = if ($null -eq $l) { $null } else { $l.CanonicalDefinition }
            RightDefinition = if ($null -eq $r) { $null } else { $r.CanonicalDefinition }
            LeftComponentHash = if ($null -eq $l) { $null } else { $l.ComponentHash }
            RightComponentHash = if ($null -eq $r) { $null } else { $r.ComponentHash }
        }
    }
}

if(-not(Test-Path -LiteralPath $CollectorPath -PathType Leaf)){
    throw "Collector not found: $CollectorPath"
}

$PolicyHash=Get-PolicyHash $ComparisonPolicy
$params=@{Database=$Database;File=$CollectorPath;EnableException=$true}
if($SqlCredential){$params.SqlCredential=$SqlCredential}

$Manifest=[System.Collections.Generic.List[object]]::new()
$Warnings=[System.Collections.Generic.List[object]]::new()

foreach($instance in $SqlInstance){
    foreach($item in Invoke-DbaQuery -SqlInstance $instance @params){
        if([string]$item.RowType -eq 'WARNING'){
            $w=[pscustomobject]@{
                SourceServer=[string]$instance;SourceDatabase=$Database
                SchemaName=[string]$item.SchemaName;ObjectName=[string]$item.ObjectName
                WarningCode=[string]$item.WarningCode;WarningMessage=[string]$item.WarningMessage
            }
            $Warnings.Add($w)
            Write-Verbose ('{0}: {1}' -f $w.WarningCode,$w.WarningMessage)
            continue
        }

        $definition=[string]$item.CanonicalDefinition
        $Manifest.Add([pscustomobject]@{
            SourceServer=[string]$instance;SourceDatabase=$Database
            Engine='SQLServer';EngineMajorVersion=15
            CollectorVersion=$CollectorVersion
            ManifestFormatVersion=$ManifestFormatVersion
            CanonicalizationVersion=$CanonicalizationVersion
            ComparisonPolicyHash=$PolicyHash
            ObjectCategory=[string]$item.ObjectCategory
            SchemaName=[string]$item.SchemaName
            ObjectName=[string]$item.ObjectName
            ComponentCategory=[string]$item.ComponentCategory
            ComponentName=[string]$item.ComponentName
            Ordinal=if(Test-DbNull $item.Ordinal){$null}else{[int]$item.Ordinal}
            DiagnosticOrdinal=if(Test-DbNull $item.DiagnosticOrdinal){$null}else{[int]$item.DiagnosticOrdinal}
            RawDefinition=[string]$item.RawDefinition
            CanonicalDefinition=$definition
            ComponentHash=Get-Sha256Hex $definition
        })
    }
}

$hashResults=foreach($g in $Manifest|Group-Object SourceServer){
    Get-HashSummary -Rows @($g.Group) -SourceServer $g.Name -SourceDatabase $Database -PolicyHash $PolicyHash
}

$db=@($hashResults.Database);$obj=@($hashResults.Objects);$sch=@($hashResults.Schemas)
$id=0
$variants=foreach($g in $db|Group-Object DatabaseHash|Sort-Object @{e='Count';Descending=$true},Name){
    $id++
    $rep=$g.Group|Sort-Object SourceServer|Select-Object -First 1
    [pscustomobject]@{
        VariantId=$id;DatabaseHash=$g.Name;ServerCount=$g.Count
        RepresentativeServer=$rep.SourceServer
        Members=($g.Group.SourceServer|Sort-Object)-join ', '
        IsLargestVariant=$id -eq 1;IsAuthoritative=$false
    }
}

$diffs=@()
if(@($variants).Count -gt 1){
    $anchor=$variants|Sort-Object VariantId|Select-Object -First 1
    $left=@($Manifest|Where-Object SourceServer -eq $anchor.RepresentativeServer)
    foreach($target in $variants|Where-Object VariantId -ne $anchor.VariantId){
        $right=@($Manifest|Where-Object SourceServer -eq $target.RepresentativeServer)
        $diffs+=Compare-ManifestRows -Left $left -Right $right -LeftVariant $anchor.VariantId -RightVariant $target.VariantId
    }
}

[pscustomobject]@{
    ComparisonPolicy=[pscustomobject]$ComparisonPolicy
    PolicyHash=$PolicyHash
    Warnings=@($Warnings)
    Manifest=@($Manifest)
    ObjectSummary=$obj
    SchemaSummary=$sch
    DatabaseSummary=$db
    VariantSummary=@($variants)
    VariantDifferences=@($diffs)
}


