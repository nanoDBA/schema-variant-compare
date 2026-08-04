/*
    SQL Server 2019 schema manifest collector.
    Table-column order is diagnostic only.
    XML, spatial, full-text, temporal, and memory-optimized features are ignored
    with warning rows consumed by PowerShell Write-Verbose.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

CREATE TABLE #Manifest
(
    RowType             varchar(10)    NOT NULL,
    ObjectCategory      varchar(30)    NULL,
    SchemaName          sysname        NULL,
    ObjectName          sysname        NULL,
    ComponentCategory   varchar(30)    NULL,
    ComponentName       nvarchar(512)  NULL,
    Ordinal             int            NULL,
    DiagnosticOrdinal   int            NULL,
    RawDefinition       nvarchar(max)  NULL,
    CanonicalDefinition nvarchar(max)  NULL,
    WarningCode         varchar(50)    NULL,
    WarningMessage      nvarchar(2000) NULL
);

/* Tables */
INSERT #Manifest
SELECT 'MANIFEST','TABLE',s.name,t.name,'TABLE',t.name,NULL,NULL,
       CONCAT('name=',QUOTENAME(s.name),'.',QUOTENAME(t.name),';'),
       CONCAT('name=',QUOTENAME(s.name),'.',QUOTENAME(t.name),';'),
       NULL,NULL
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0;

/* Columns: c.column_id is diagnostic only. */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',s.name,t.name,'COLUMN',c.name,NULL,c.column_id,
    CONCAT(
        'ordinal=',c.column_id,';',
        'name=',QUOTENAME(c.name),';',
        'type_schema=',QUOTENAME(SCHEMA_NAME(ty.schema_id)),';',
        'type=',QUOTENAME(ty.name),';',
        'max_length=',c.max_length,';',
        'precision=',c.precision,';',
        'scale=',c.scale,';',
        'nullable=',CONVERT(tinyint,c.is_nullable),';',
        'collation=',COALESCE(QUOTENAME(c.collation_name),'<NULL>'),';',
        'identity=',CONVERT(tinyint,c.is_identity),';',
        'identity_seed=',COALESCE(CONVERT(nvarchar(100),ic.seed_value),'<NULL>'),';',
        'identity_increment=',COALESCE(CONVERT(nvarchar(100),ic.increment_value),'<NULL>'),';',
        'computed=',CONVERT(tinyint,c.is_computed),';',
        'computed_persisted=',COALESCE(CONVERT(varchar(1),CONVERT(tinyint,cc.is_persisted)),'<NULL>'),';',
        'computed_definition=',COALESCE(LTRIM(RTRIM(cc.definition)),'<NULL>'),';'
    ),
    CONCAT(
        'name=',QUOTENAME(c.name),';',
        'type_schema=',QUOTENAME(SCHEMA_NAME(ty.schema_id)),';',
        'type=',QUOTENAME(ty.name),';',
        'max_length=',c.max_length,';',
        'precision=',c.precision,';',
        'scale=',c.scale,';',
        'nullable=',CONVERT(tinyint,c.is_nullable),';',
        'collation=',COALESCE(QUOTENAME(c.collation_name),'<NULL>'),';',
        'identity=',CONVERT(tinyint,c.is_identity),';',
        'identity_seed=',COALESCE(CONVERT(nvarchar(100),ic.seed_value),'<NULL>'),';',
        'identity_increment=',COALESCE(CONVERT(nvarchar(100),ic.increment_value),'<NULL>'),';',
        'computed=',CONVERT(tinyint,c.is_computed),';',
        'computed_persisted=',COALESCE(CONVERT(varchar(1),CONVERT(tinyint,cc.is_persisted)),'<NULL>'),';',
        'computed_definition=',COALESCE(LTRIM(RTRIM(cc.definition)),'<NULL>'),';'
    ),
    NULL,NULL
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id=t.schema_id
JOIN sys.columns c ON c.object_id=t.object_id
JOIN sys.types ty ON ty.user_type_id=c.user_type_id
LEFT JOIN sys.identity_columns ic ON ic.object_id=c.object_id AND ic.column_id=c.column_id
LEFT JOIN sys.computed_columns cc ON cc.object_id=c.object_id AND cc.column_id=c.column_id
WHERE t.is_ms_shipped=0;

/* Defaults */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',s.name,t.name,'DEFAULT_CONSTRAINT',
    CASE WHEN dc.is_system_named=1 THEN CONCAT('<SYSTEM>:',c.name) ELSE dc.name END,
    NULL,c.column_id,
    CONCAT('name=',QUOTENAME(dc.name),';column=',QUOTENAME(c.name),';definition=',LTRIM(RTRIM(dc.definition)),';'),
    CONCAT('name=',CASE WHEN dc.is_system_named=1 THEN '<SYSTEM>' ELSE QUOTENAME(dc.name) END,
           ';column=',QUOTENAME(c.name),';definition=',LTRIM(RTRIM(dc.definition)),';'),
    NULL,NULL
FROM sys.default_constraints dc
JOIN sys.tables t ON t.object_id=dc.parent_object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
JOIN sys.columns c ON c.object_id=dc.parent_object_id AND c.column_id=dc.parent_column_id
WHERE t.is_ms_shipped=0;

/* Checks */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',s.name,t.name,'CHECK_CONSTRAINT',
    CASE WHEN ck.is_system_named=1
         THEN CONCAT('<SYSTEM>:',ck.parent_column_id,':',
              CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),LTRIM(RTRIM(ck.definition)))),2))
         ELSE ck.name END,
    NULL,NULL,
    CONCAT('name=',QUOTENAME(ck.name),';definition=',LTRIM(RTRIM(ck.definition)),';'),
    CONCAT('name=',CASE WHEN ck.is_system_named=1 THEN '<SYSTEM>' ELSE QUOTENAME(ck.name) END,
           ';definition=',LTRIM(RTRIM(ck.definition)),
           ';not_for_replication=',CONVERT(tinyint,ck.is_not_for_replication),
           ';disabled=',CONVERT(tinyint,ck.is_disabled),
           ';trusted=',CONVERT(tinyint,1-ck.is_not_trusted),';'),
    NULL,NULL
FROM sys.check_constraints ck
JOIN sys.tables t ON t.object_id=ck.parent_object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0;

/* PK/UQ: key order strict */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',s.name,t.name,
    CASE kc.type WHEN 'PK' THEN 'PRIMARY_KEY' ELSE 'UNIQUE_CONSTRAINT' END,
    CASE WHEN kc.is_system_named=1 THEN CONCAT('<SYSTEM>:',kc.type,':',k.KeyColumns) ELSE kc.name END,
    NULL,NULL,
    CONCAT('name=',QUOTENAME(kc.name),';index_type=',i.type_desc,';keys=',k.KeyColumns,';'),
    CONCAT('name=',CASE WHEN kc.is_system_named=1 THEN '<SYSTEM>' ELSE QUOTENAME(kc.name) END,
           ';index_type=',i.type_desc,';keys=',k.KeyColumns,';'),
    NULL,NULL
FROM sys.key_constraints kc
JOIN sys.tables t ON t.object_id=kc.parent_object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
JOIN sys.indexes i ON i.object_id=kc.parent_object_id AND i.index_id=kc.unique_index_id
CROSS APPLY (
    SELECT STRING_AGG(CONCAT(QUOTENAME(c.name),
             CASE WHEN ic.is_descending_key=1 THEN ' DESC' ELSE ' ASC' END),',')
           WITHIN GROUP (ORDER BY ic.key_ordinal) KeyColumns
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE ic.object_id=kc.parent_object_id
      AND ic.index_id=kc.unique_index_id
      AND ic.key_ordinal>0
) k
WHERE t.is_ms_shipped=0;

/* Foreign keys: pairing/order strict */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',ps.name,pt.name,'FOREIGN_KEY',
    CASE WHEN fk.is_system_named=1
         THEN CONCAT('<SYSTEM>:',QUOTENAME(rs.name),'.',QUOTENAME(rt.name),':',m.ColumnMap)
         ELSE fk.name END,
    NULL,NULL,
    CONCAT('name=',QUOTENAME(fk.name),';referenced=',QUOTENAME(rs.name),'.',QUOTENAME(rt.name),
           ';columns=',m.ColumnMap,';'),
    CONCAT('name=',CASE WHEN fk.is_system_named=1 THEN '<SYSTEM>' ELSE QUOTENAME(fk.name) END,
           ';referenced=',QUOTENAME(rs.name),'.',QUOTENAME(rt.name),
           ';columns=',m.ColumnMap,
           ';delete_action=',fk.delete_referential_action_desc,
           ';update_action=',fk.update_referential_action_desc,
           ';not_for_replication=',CONVERT(tinyint,fk.is_not_for_replication),
           ';disabled=',CONVERT(tinyint,fk.is_disabled),
           ';trusted=',CONVERT(tinyint,1-fk.is_not_trusted),';'),
    NULL,NULL
FROM sys.foreign_keys fk
JOIN sys.tables pt ON pt.object_id=fk.parent_object_id
JOIN sys.schemas ps ON ps.schema_id=pt.schema_id
JOIN sys.tables rt ON rt.object_id=fk.referenced_object_id
JOIN sys.schemas rs ON rs.schema_id=rt.schema_id
CROSS APPLY (
    SELECT STRING_AGG(CONCAT(QUOTENAME(pc.name),'=>',QUOTENAME(rc.name)),',')
           WITHIN GROUP (ORDER BY fkc.constraint_column_id) ColumnMap
    FROM sys.foreign_key_columns fkc
    JOIN sys.columns pc ON pc.object_id=fkc.parent_object_id AND pc.column_id=fkc.parent_column_id
    JOIN sys.columns rc ON rc.object_id=fkc.referenced_object_id AND rc.column_id=fkc.referenced_column_id
    WHERE fkc.constraint_object_id=fk.object_id
) m
WHERE pt.is_ms_shipped=0;

/* Rowstore indexes only. INCLUDE order canonicalized by name. */
INSERT #Manifest
SELECT
    'MANIFEST','TABLE',s.name,t.name,'INDEX',i.name,NULL,NULL,
    CONCAT('name=',QUOTENAME(i.name),';type=',i.type_desc,';keys=',COALESCE(k.KeyColumns,''),
           ';includes=',COALESCE(x.IncludeColumnsByOrdinal,''),';'),
    CONCAT('name=',QUOTENAME(i.name),
           ';type=',i.type_desc,
           ';unique=',CONVERT(tinyint,i.is_unique),
           ';disabled=',CONVERT(tinyint,i.is_disabled),
           ';ignore_dup_key=',CONVERT(tinyint,i.ignore_dup_key),
           ';filter=',COALESCE(LTRIM(RTRIM(i.filter_definition)),'<NULL>'),
           ';keys=',COALESCE(k.KeyColumns,''),
           ';includes=',COALESCE(x.IncludeColumnsCanonical,''),';'),
    NULL,NULL
FROM sys.indexes i
JOIN sys.tables t ON t.object_id=i.object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
LEFT JOIN sys.key_constraints kc ON kc.parent_object_id=i.object_id AND kc.unique_index_id=i.index_id
OUTER APPLY (
    SELECT STRING_AGG(CONCAT(QUOTENAME(c.name),
             CASE WHEN ic.is_descending_key=1 THEN ' DESC' ELSE ' ASC' END),',')
           WITHIN GROUP (ORDER BY ic.key_ordinal) KeyColumns
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal>0
) k
OUTER APPLY (
    SELECT
      STRING_AGG(QUOTENAME(c.name),',') WITHIN GROUP (ORDER BY ic.index_column_id) IncludeColumnsByOrdinal,
      STRING_AGG(QUOTENAME(c.name),',') WITHIN GROUP (ORDER BY c.name) IncludeColumnsCanonical
    FROM sys.index_columns ic
    JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.is_included_column=1
) x
WHERE t.is_ms_shipped=0
  AND i.index_id>0
  AND i.type IN (1,2)
  AND i.is_hypothetical=0
  AND i.name IS NOT NULL
  AND kc.object_id IS NULL;

/* Warning rows */
INSERT #Manifest (RowType,SchemaName,ObjectName,WarningCode,WarningMessage)
SELECT 'WARNING',s.name,t.name,'TEMPORAL_TABLE_IGNORED',
       CONCAT('Ignoring temporal-table attributes for ',QUOTENAME(s.name),'.',QUOTENAME(t.name),'.')
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0 AND t.temporal_type<>0;

INSERT #Manifest (RowType,SchemaName,ObjectName,WarningCode,WarningMessage)
SELECT 'WARNING',s.name,t.name,'MEMORY_OPTIMIZED_IGNORED',
       CONCAT('Ignoring memory-optimized attributes for ',QUOTENAME(s.name),'.',QUOTENAME(t.name),'.')
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0 AND t.is_memory_optimized=1;

INSERT #Manifest (RowType,SchemaName,ObjectName,WarningCode,WarningMessage)
SELECT 'WARNING',s.name,t.name,
       CASE i.type WHEN 3 THEN 'XML_INDEX_IGNORED'
                   WHEN 4 THEN 'SPATIAL_INDEX_IGNORED'
                   ELSE 'NON_ROWSTORE_INDEX_IGNORED' END,
       CONCAT('Ignoring ',i.type_desc,' ',QUOTENAME(s.name),'.',QUOTENAME(t.name),'.',QUOTENAME(i.name),'.')
FROM sys.indexes i
JOIN sys.tables t ON t.object_id=i.object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0 AND i.type IN (3,4);

INSERT #Manifest (RowType,SchemaName,ObjectName,WarningCode,WarningMessage)
SELECT 'WARNING',s.name,t.name,'FULLTEXT_INDEX_IGNORED',
       CONCAT('Ignoring full-text index on ',QUOTENAME(s.name),'.',QUOTENAME(t.name),'.')
FROM sys.fulltext_indexes fi
JOIN sys.tables t ON t.object_id=fi.object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0;

SELECT *
FROM #Manifest
ORDER BY CASE RowType WHEN 'MANIFEST' THEN 0 ELSE 1 END,
         SchemaName,ObjectName,ComponentCategory,ISNULL(Ordinal,-1),ComponentName,WarningCode;
