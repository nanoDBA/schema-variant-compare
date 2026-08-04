/*
    Initial SQL Server 2019 schema manifest collector.

    Returns one row per comparable component. This file is intentionally a
    scaffold: table and column rows are implemented first, with constraints and
    indexes to be added in subsequent commits.
*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

WITH BaseTables AS
(
    SELECT
        s.name AS SchemaName,
        t.name AS ObjectName,
        t.object_id
    FROM sys.tables AS t
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0
),
ColumnDefinitions AS
(
    SELECT
        bt.SchemaName,
        bt.ObjectName,
        c.column_id AS Ordinal,
        c.name AS ComponentName,
        CONCAT(
            'name=', QUOTENAME(c.name), ';',
            'type=', QUOTENAME(ty.name), ';',
            'max_length=', c.max_length, ';',
            'precision=', c.precision, ';',
            'scale=', c.scale, ';',
            'nullable=', CONVERT(tinyint, c.is_nullable), ';',
            'collation=', COALESCE(QUOTENAME(c.collation_name), '<NULL>'), ';',
            'identity=', CONVERT(tinyint, c.is_identity), ';',
            'computed=', CONVERT(tinyint, c.is_computed), ';',
            'rowguidcol=', CONVERT(tinyint, c.is_rowguidcol), ';',
            'sparse=', CONVERT(tinyint, c.is_sparse), ';'
        ) AS CanonicalDefinition
    FROM BaseTables AS bt
    INNER JOIN sys.columns AS c
        ON c.object_id = bt.object_id
    INNER JOIN sys.types AS ty
        ON ty.user_type_id = c.user_type_id
)
SELECT
    CAST('TABLE' AS varchar(30)) AS ObjectCategory,
    bt.SchemaName,
    bt.ObjectName,
    CAST('TABLE' AS varchar(30)) AS ComponentCategory,
    bt.ObjectName AS ComponentName,
    CAST(NULL AS int) AS Ordinal,
    CAST('is_memory_optimized=0;' AS nvarchar(max)) AS CanonicalDefinition
FROM BaseTables AS bt

UNION ALL

SELECT
    'TABLE',
    cd.SchemaName,
    cd.ObjectName,
    'COLUMN',
    cd.ComponentName,
    cd.Ordinal,
    CONVERT(nvarchar(max), cd.CanonicalDefinition)
FROM ColumnDefinitions AS cd

ORDER BY
    SchemaName,
    ObjectName,
    ComponentCategory,
    Ordinal,
    ComponentName;
