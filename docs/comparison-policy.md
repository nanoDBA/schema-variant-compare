# Comparison policy

The policy is part of the hash contract.

- Table column order: ignored for equivalence; retained as `DiagnosticOrdinal`.
- Index key order and ASC/DESC: strict.
- Primary-key and unique-constraint column order: strict.
- Foreign-key column pairing/order: strict.
- Included-column order: ignored.
- Explicit constraint names: compared.
- System-generated constraint names: ignored.
- Disabled index state: compared.
- Fill factor, compression, filegroup, and partition scheme: ignored.
- XML, spatial, full-text, temporal, and memory-optimized attributes: ignored with verbose warnings.

Every run emits collector, manifest-format, canonicalization, and policy-hash metadata.
