BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../src/Compare-DatabaseSchema.ps1'
    $collectorPath = Join-Path $PSScriptRoot '../src/sqlserver/Get-SchemaManifest.sql'
}

Describe 'Project files' {
    It 'contains the PowerShell comparison script' {
        $scriptPath | Should -Exist
    }

    It 'contains the SQL Server collector' {
        $collectorPath | Should -Exist
    }

    It 'does not contain Bash-style continuation characters in PowerShell' {
        (Get-Content -Raw $scriptPath) | Should -Not -Match '(?m)\\$'
    }
}

Describe 'SQL Server collector contract' {
    BeforeAll {
        $collector = Get-Content -Raw $collectorPath
    }

    It 'emits required manifest columns' {
        foreach ($name in @(
            'ObjectCategory', 'SchemaName', 'ObjectName',
            'ComponentCategory', 'ComponentName', 'Ordinal',
            'CanonicalDefinition'
        )) {
            $collector | Should -Match $name
        }
    }

    It 'collects primary keys, foreign keys, checks, and indexes' {
        $collector | Should -Match 'PRIMARY_KEY'
        $collector | Should -Match 'FOREIGN_KEY'
        $collector | Should -Match 'CHECK_CONSTRAINT'
        $collector | Should -Match "'INDEX'"
    }
}
