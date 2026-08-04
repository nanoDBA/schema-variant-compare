# Prior art

Projects worth learning from:

- Microsoft DacFx: broad SQL Server schema modeling and a useful integration-test oracle.
- SchemaCrawler: deterministic offline manifests and explicit sorting/filter policies.
- sqldef: separation of schema modeling, comparison, and migration generation.
- Stripe pg-schema-diff: explicit unsupported-object handling and engine-version awareness.

Applied lessons:

- Version the manifest and canonicalization rules.
- Include policy in the root hash.
- Preserve raw and canonical definitions.
- Warn explicitly when features are intentionally ignored.
- Never treat incomplete metadata visibility as a valid complete manifest.
- Keep comparison separate from remediation.
