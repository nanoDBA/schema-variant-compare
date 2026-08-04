BeforeAll {
    $integrationRoot = Join-Path $PSScriptRoot 'integration'
    $runner = Join-Path $integrationRoot 'Invoke-IntegrationTest.ps1'
    $compose = Join-Path $integrationRoot 'docker-compose.yml'
}

Describe 'Integration harness files' {
    It 'contains the integration runner' {
        $runner | Should -Exist
    }

    It 'contains the Docker Compose definition' {
        $compose | Should -Exist
    }

    It 'contains equivalent and drift seed scripts' {
        Join-Path $integrationRoot 'sql/seed-a.sql' | Should -Exist
        Join-Path $integrationRoot 'sql/seed-b-equivalent.sql' | Should -Exist
        Join-Path $integrationRoot 'sql/apply-drift-b.sql' | Should -Exist
    }

    It 'tests one equivalent variant and two drifted variants' {
        $content = Get-Content -Raw $runner
        $content | Should -Match 'Equivalent logical schemas should produce one variant'
        $content | Should -Match 'Intentional drift should produce two variants'
    }
}
