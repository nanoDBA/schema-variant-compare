# Design

## Problem

Multiple SQL Server instances host databases with the same name. The goal is to determine which schemas are identical and to identify exact differences without linked servers and without assuming one instance is the baseline.

## Observed variants

Each collected database manifest receives a `DatabaseHash`. Databases sharing that hash are grouped into a variant.

Example:

```text
Variant 1: SQL01, SQL02, SQL04
Variant 2: SQL03
Variant 3: SQL05
```

The largest variant may be used as the default display anchor because it minimizes comparison noise. It is not authoritative.

## Manifest-first design

The detailed manifest is the source of truth. Hashes are accelerators.

Logical component key:

```text
ObjectCategory
SchemaName
ObjectName
ComponentCategory
ComponentName
Ordinal
```

Do not include SQL Server internal identifiers such as `object_id`, `column_id`, `index_id`, or constraint object IDs in the comparison key or canonical definition.

## Hierarchical hashes

1. `ComponentHash`: hash of canonical component definition.
2. `ObjectHash`: hash of sorted component signatures for one object.
3. `SchemaHash`: hash of sorted object signatures for one schema.
4. `DatabaseHash`: hash of sorted schema signatures.

## Comparison strategy

1. Group databases by `DatabaseHash`.
2. Choose one representative manifest per variant.
3. Compare representatives instead of every server pair.
4. Emit missing, extra, and changed component rows.
5. Retain full membership so a difference reported for a variant applies to every member.

## Future authoritative reference

A later release may allow an approved manifest to be promoted from:

- a deployment artifact
- source control
- a release snapshot
- an operator-selected observed variant

This separates observed consistency from expected correctness.
