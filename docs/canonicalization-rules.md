# Canonicalization rules

## General

- Use schema and object names, not internal IDs.
- Preserve column ordinal.
- Preserve index key ordinal and sort direction.
- Sort included index columns by normalized column name because include order is not semantically meaningful.
- Use explicit separators and property names in canonical strings.
- Use invariant formatting for numbers and booleans.

## Generated constraint names

Constraint names marked by SQL Server as system-generated are not semantic identifiers.

For system-named defaults, checks, foreign keys, primary keys, and unique constraints, build identity from the parent object and semantic definition rather than the generated name.

Explicitly named constraints remain name-sensitive in the initial design.

## Defaults and expressions

Initial normalization is conservative:

- normalize CRLF and CR to LF
- trim surrounding whitespace
- do not rewrite expressions
- do not remove redundant parentheses
- do not parse and regenerate T-SQL

False positives are preferable to false equivalence.

## Modules

Views, procedures, functions, and triggers will be added after the structural collector is stable.

Planned normalization:

- normalize line endings
- remove trailing whitespace from each line
- remove trailing blank lines
- preserve comments
- preserve internal whitespace
- retain relevant `sys.sql_modules` settings such as ANSI NULL and quoted identifier state
