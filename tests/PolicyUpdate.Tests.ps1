BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../src/Compare-DatabaseSchema.ps1'
    $collectorPath = Join-Path $PSScriptRoot '../src/sqlserver/Get-SchemaManifest.sql'
}

Describe 'Policy update' {
    It 'includes versioned policy metadata' {
        $s=Get-Content -Raw $scriptPath
        $s|Should -Match 'ManifestFormatVersion'
        $s|Should -Match 'CanonicalizationVersion'
        $s|Should -Match 'ComparisonPolicyHash'
    }

    It 'uses verbose warnings for ignored features' {
        (Get-Content -Raw $scriptPath)|Should -Match 'Write-Verbose'
    }

    It 'keeps table column order diagnostic only' {
        $q=Get-Content -Raw $collectorPath
        $q|Should -Match "'COLUMN',c\.name,NULL,c\.column_id"
    }

    It 'restricts collected indexes to rowstore indexes' {
        (Get-Content -Raw $collectorPath)|Should -Match 'i\.type IN \(1,2\)'
    }

    It 'warns for ignored index and table features' {
        $q=Get-Content -Raw $collectorPath
        foreach($x in @('XML_INDEX_IGNORED','SPATIAL_INDEX_IGNORED','FULLTEXT_INDEX_IGNORED','TEMPORAL_TABLE_IGNORED','MEMORY_OPTIMIZED_IGNORED')){
            $q|Should -Match $x
        }
    }

    It 'does not call the largest variant authoritative' {
        (Get-Content -Raw $scriptPath)|Should -Match 'IsAuthoritative=\$false'
    }
}
