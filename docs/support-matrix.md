# SQL Server support matrix

| Feature | Status | Behavior |
|---|---|---|
| Tables | Supported | Logical identity compared |
| Table column order | Diagnostic only | Ignored in hashes |
| Columns | Supported | Name/type/length/precision/scale/nullability/collation strict |
| Identity | Supported | Strict |
| Computed columns | Supported | Definition and persistence strict |
| Defaults | Supported | Definition strict; system names ignored |
| Checks | Supported | Definition and state strict |
| Primary keys | Supported | Key order and direction strict |
| Unique constraints | Supported | Key order and direction strict |
| Foreign keys | Supported | Pairing/order/actions/state strict |
| Rowstore indexes | Supported | Key order strict; INCLUDE order ignored |
| XML indexes | Excluded | Verbose warning |
| Spatial indexes | Excluded | Verbose warning |
| Full-text indexes | Excluded | Verbose warning |
| Temporal attributes | Excluded | Base table still compared; verbose warning |
| Memory-optimized attributes | Excluded | Base table still compared; verbose warning |
| Permissions/roles | Excluded | Ignored |
| Views/procedures/functions/triggers | Planned | Not collected yet |
