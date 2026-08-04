# Integration tests

The integration harness starts two disposable SQL Server 2019 Developer containers.

It validates:

1. Different physical table-column order does not create a new variant.
2. Different system-generated default names do not create a new variant.
3. Different included-column order does not create a new variant.
4. Changed index key order creates drift.
5. Changed column length creates drift.
6. Changed foreign-key action creates drift.

## Requirements

- Docker with the Compose plugin
- PowerShell 7
- dbatools
- Pester is not required for this harness

## Run

From the repository root:

```powershell
$env:MSSQL_SA_PASSWORD = 'Use-A-Strong-Temporary-Password1!'
./tests/integration/Invoke-IntegrationTest.ps1
```

Keep the containers for inspection:

```powershell
./tests/integration/Invoke-IntegrationTest.ps1 -KeepContainers
```

Then connect to:

- `localhost,14331`
- `localhost,14332`

The database name on both instances is `SchemaCompareTest`.

## Notes

The test uses SQL Server Developer Edition in containers. It does not touch existing SQL Server instances.
