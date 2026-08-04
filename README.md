# schema-variant-compare

Compare the schema of the same SQL Server database across multiple instances without assuming that any one server is authoritative.

The project collects a canonical schema manifest from each database, computes hierarchical SHA-256 hashes, groups identical databases into schema variants, and emits component-level differences between variants.

## Status

Initial design and SQL Server 2019 scaffold. The first collector focuses on structural schema objects:

- schemas
- tables
- columns
- computed and identity properties
- defaults
- primary keys and unique constraints
- foreign keys
- check constraints
- user-created indexes

The following are intentionally excluded from v1:

- permissions and roles
- partitioning
- filegroups
- compression
- fill factor
- online/resumable index settings
- CDC and replication artifacts

## Core model

Each server produces manifest rows with a stable logical key and a canonical definition.

```text
ObjectCategory
SchemaName
ObjectName
ComponentCategory
ComponentName
Ordinal
CanonicalDefinition
ComponentHash
```

Hashes roll upward:

```text
ComponentHash -> ObjectHash -> SchemaHash -> DatabaseHash
```

Databases with the same root hash form an observed schema variant. One manifest is selected as the representative of each variant, but no variant is automatically declared correct.

## Planned workflow

```powershell
$instances = 'SQL01','SQL02','SQL03'

./src/Compare-DatabaseSchema.ps1 \
    -SqlInstance $instances \
    -Database AppDb
```

Expected outputs:

- variant membership table
- database/schema/object hashes
- detailed missing, extra, and changed components
- optional staging-table upload for SQL-side reporting

## Requirements

- PowerShell 7 recommended
- dbatools
- SQL Server 2019 or later for the initial collector

## Repository layout

```text
src/
  Compare-DatabaseSchema.ps1
  sqlserver/
    Get-SchemaManifest.sql
docs/
  design.md
  canonicalization-rules.md
examples/
  Compare-MultipleInstances.ps1
tests/
```
