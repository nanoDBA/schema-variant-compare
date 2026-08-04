/*
    SQL Server 2019 schema manifest collector.

    Emits one row per independently comparable schema component. Object IDs and
    other instance-local identifiers are used only for catalog joins and never
    appear in comparison keys or canonical definitions.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

CREATE TABLE #Manifest
(
    ObjectCategory      varchar(30)   NOT NULL,
    SchemaName          sysname       NOT NULL,
    ObjectName          sysname       NOT NULL,
    ComponentCategory   varchar(30)   NOT NULL,
    ComponentName       nvarchar(512) NOT NULL,
    Ordinal             int           NULL,
    CanonicalDefinition nvarchar(max) NOT NULL
);

/* Tables */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    s.name,
    t.name,
    'TABLE',
    t.name,
    NULL,
    CONCAT(
        'memory_optimized=', CONVERT(tinyint, t.is_memory_optimized), ';',
        'temporal_type=', t.temporal_type, ';'
    )
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0;

/* Columns, including identity, computed expression, and bound default */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    s.name,
    t.name,
    'COLUMN',
    c.name,
    c.column_id,
    CONCAT(
        'name=', QUOTENAME(c.name), ';',
        'type_schema=', QUOTENAME(SCHEMA_NAME(ty.schema_id)), ';',
        'type=', QUOTENAME(ty.name), ';',
        'max_length=', c.max_length, ';',
        'precision=', c.precision, ';',
        'scale=', c.scale, ';',
        'nullable=', CONVERT(tinyint, c.is_nullable), ';',
        'collation=', COALESCE(QUOTENAME(c.collation_name), '<NULL>'), ';',
        'identity=', CONVERT(tinyint, c.is_identity), ';',
        'identity_seed=', COALESCE(CONVERT(nvarchar(100), ic.seed_value), '<NULL>'), ';',
        'identity_increment=', COALESCE(CONVERT(nvarchar(100), ic.increment_value), '<NULL>'), ';',
        'computed=', CONVERT(tinyint, c.is_computed), ';',
        'computed_persisted=', COALESCE(CONVERT(varchar(1), CONVERT(tinyint, cc.is_persisted)), '<NULL>'), ';',
        'computed_definition=', COALESCE(LTRIM(RTRIM(cc.definition)), '<NULL>'), ';',
        'default_definition=', COALESCE(LTRIM(RTRIM(dc.definition)), '<NULL>'), ';',
        'rowguidcol=', CONVERT(tinyint, c.is_rowguidcol), ';',
        'sparse=', CONVERT(tinyint, c.is_sparse), ';'
    )
FROM sys.tables AS t
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
JOIN sys.columns AS c
    ON c.object_id = t.object_id
JOIN sys.types AS ty
    ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.identity_columns AS ic
    ON ic.object_id = c.object_id
   AND ic.column_id = c.column_id
LEFT JOIN sys.computed_columns AS cc
    ON cc.object_id = c.object_id
   AND cc.column_id = c.column_id
LEFT JOIN sys.default_constraints AS dc
    ON dc.parent_object_id = c.object_id
   AND dc.parent_column_id = c.column_id
WHERE t.is_ms_shipped = 0;

/* Check constraints. System-generated names are excluded from identity. */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    s.name,
    t.name,
    'CHECK_CONSTRAINT',
    CASE
        WHEN ck.is_system_named = 1 THEN CONCAT('<SYSTEM>:', ck.parent_column_id, ':', CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(varbinary(max), LTRIM(RTRIM(ck.definition)))), 2))
        ELSE ck.name
    END,
    NULL,
    CONCAT(
        'name=', CASE WHEN ck.is_system_named = 1 THEN '<SYSTEM>' ELSE QUOTENAME(ck.name) END, ';',
        'definition=', LTRIM(RTRIM(ck.definition)), ';',
        'not_for_replication=', CONVERT(tinyint, ck.is_not_for_replication), ';',
        'disabled=', CONVERT(tinyint, ck.is_disabled), ';',
        'trusted=', CONVERT(tinyint, 1 - ck.is_not_trusted), ';'
    )
FROM sys.check_constraints AS ck
JOIN sys.tables AS t
    ON t.object_id = ck.parent_object_id
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0;

/* Primary keys and unique constraints. */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    s.name,
    t.name,
    CASE kc.type WHEN 'PK' THEN 'PRIMARY_KEY' ELSE 'UNIQUE_CONSTRAINT' END,
    CASE
        WHEN kc.is_system_named = 1 THEN CONCAT('<SYSTEM>:', kc.type, ':', keys.KeyColumns)
        ELSE kc.name
    END,
    NULL,
    CONCAT(
        'name=', CASE WHEN kc.is_system_named = 1 THEN '<SYSTEM>' ELSE QUOTENAME(kc.name) END, ';',
        'index_type=', i.type_desc, ';',
        'keys=', keys.KeyColumns, ';'
    )
FROM sys.key_constraints AS kc
JOIN sys.tables AS t
    ON t.object_id = kc.parent_object_id
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
JOIN sys.indexes AS i
    ON i.object_id = kc.parent_object_id
   AND i.index_id = kc.unique_index_id
CROSS APPLY
(
    SELECT STRING_AGG(
        CONCAT(QUOTENAME(c.name), CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END),
        ','
    ) WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns
    FROM sys.index_columns AS ic
    JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
    WHERE ic.object_id = kc.parent_object_id
      AND ic.index_id = kc.unique_index_id
      AND ic.key_ordinal > 0
) AS keys
WHERE t.is_ms_shipped = 0;

/* Foreign keys. System-generated names are excluded from identity. */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    ps.name,
    pt.name,
    'FOREIGN_KEY',
    CASE
        WHEN fk.is_system_named = 1 THEN CONCAT('<SYSTEM>:', QUOTENAME(rs.name), '.', QUOTENAME(rt.name), ':', cols.ColumnMap)
        ELSE fk.name
    END,
    NULL,
    CONCAT(
        'name=', CASE WHEN fk.is_system_named = 1 THEN '<SYSTEM>' ELSE QUOTENAME(fk.name) END, ';',
        'referenced=', QUOTENAME(rs.name), '.', QUOTENAME(rt.name), ';',
        'columns=', cols.ColumnMap, ';',
        'delete_action=', fk.delete_referential_action_desc, ';',
        'update_action=', fk.update_referential_action_desc, ';',
        'not_for_replication=', CONVERT(tinyint, fk.is_not_for_replication), ';',
        'disabled=', CONVERT(tinyint, fk.is_disabled), ';',
        'trusted=', CONVERT(tinyint, 1 - fk.is_not_trusted), ';'
    )
FROM sys.foreign_keys AS fk
JOIN sys.tables AS pt
    ON pt.object_id = fk.parent_object_id
JOIN sys.schemas AS ps
    ON ps.schema_id = pt.schema_id
JOIN sys.tables AS rt
    ON rt.object_id = fk.referenced_object_id
JOIN sys.schemas AS rs
    ON rs.schema_id = rt.schema_id
CROSS APPLY
(
    SELECT STRING_AGG(
        CONCAT(QUOTENAME(pc.name), '=>', QUOTENAME(rc.name)),
        ','
    ) WITHIN GROUP (ORDER BY fkc.constraint_column_id) AS ColumnMap
    FROM sys.foreign_key_columns AS fkc
    JOIN sys.columns AS pc
        ON pc.object_id = fkc.parent_object_id
       AND pc.column_id = fkc.parent_column_id
    JOIN sys.columns AS rc
        ON rc.object_id = fkc.referenced_object_id
       AND rc.column_id = fkc.referenced_column_id
    WHERE fkc.constraint_object_id = fk.object_id
) AS cols
WHERE pt.is_ms_shipped = 0;

/* User-created indexes that do not back PK/UQ constraints. */
INSERT #Manifest
(
    ObjectCategory, SchemaName, ObjectName, ComponentCategory,
    ComponentName, Ordinal, CanonicalDefinition
)
SELECT
    'TABLE',
    s.name,
    t.name,
    'INDEX',
    i.name,
    NULL,
    CONCAT(
        'name=', QUOTENAME(i.name), ';',
        'type=', i.type_desc, ';',
        'unique=', CONVERT(tinyint, i.is_unique), ';',
        'disabled=', CONVERT(tinyint, i.is_disabled), ';',
        'ignore_dup_key=', CONVERT(tinyint, i.ignore_dup_key), ';',
        'filter=', COALESCE(LTRIM(RTRIM(i.filter_definition)), '<NULL>'), ';',
        'keys=', COALESCE(keys.KeyColumns, ''), ';',
        'includes=', COALESCE(includes.IncludeColumns, ''), ';'
    )
FROM sys.indexes AS i
JOIN sys.tables AS t
    ON t.object_id = i.object_id
JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
LEFT JOIN sys.key_constraints AS kc
    ON kc.parent_object_id = i.object_id
   AND kc.unique_index_id = i.index_id
OUTER APPLY
(
    SELECT STRING_AGG(
        CONCAT(QUOTENAME(c.name), CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END),
        ','
    ) WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns
    FROM sys.index_columns AS ic
    JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
    WHERE ic.object_id = i.object_id
      AND ic.index_id = i.index_id
      AND ic.key_ordinal > 0
) AS keys
OUTER APPLY
(
    SELECT STRING_AGG(QUOTENAME(c.name), ',') WITHIN GROUP (ORDER BY c.name) AS IncludeColumns
    FROM sys.index_columns AS ic
    JOIN sys.columns AS c
        ON c.object_id = ic.object_id
       AND c.column_id = ic.column_id
    WHERE ic.object_id = i.object_id
      AND ic.index_id = i.index_id
      AND ic.is_included_column = 1
) AS includes
WHERE t.is_ms_shipped = 0
  AND i.index_id > 0
  AND i.is_hypothetical = 0
  AND i.name IS NOT NULL
  AND kc.object_id IS NULL;

SELECT
    ObjectCategory,
    SchemaName,
    ObjectName,
    ComponentCategory,
    ComponentName,
    Ordinal,
    CanonicalDefinition
FROM #Manifest
ORDER BY
    SchemaName,
    ObjectName,
    ComponentCategory,
    ISNULL(Ordinal, -1),
    ComponentName;
