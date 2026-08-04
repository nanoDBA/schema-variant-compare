Describe 'schema-variant-compare' {
    It 'has a SQL Server collector' {
        Test-Path "$PSScriptRoot/../src/sqlserver/Get-SchemaManifest.sql" | Should -BeTrue
    }

    It 'has a PowerShell entry point' {
        Test-Path "$PSScriptRoot/../src/Compare-DatabaseSchema.ps1" | Should -BeTrue
    }
}
