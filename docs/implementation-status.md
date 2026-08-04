# Implementation status

Implemented:

- table and column manifest rows
- defaults attached to columns
- computed-column definitions
- primary keys and unique constraints
- check constraints
- foreign keys
- user-created indexes
- component, object, schema, and database SHA-256 hashes
- observed variant grouping
- detailed comparison of the largest variant against each other variant

Known limitations:

- views, procedures, functions, and triggers are not collected yet
- no SQL staging-table persistence yet
- no approved-manifest workflow yet
- current detailed comparison uses the largest observed variant as a display anchor, not an authority
