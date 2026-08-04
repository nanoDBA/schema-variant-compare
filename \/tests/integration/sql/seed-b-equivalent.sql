SET NOCOUNT ON;
IF DB_ID(N'SchemaCompareTest') IS NOT NULL
BEGIN
    ALTER DATABASE SchemaCompareTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SchemaCompareTest;
END;
CREATE DATABASE SchemaCompareTest;
GO
USE SchemaCompareTest;
GO

/* Same logical columns as sql-a, but physical table-column order differs. */
CREATE TABLE dbo.Customer
(
    CustomerId int IDENTITY(1,1) NOT NULL,
    CreatedAt datetime2(3) NOT NULL DEFAULT (sysutcdatetime()),
    Status varchar(20) NOT NULL DEFAULT ('Active'),
    DisplayName nvarchar(200) NULL,
    CustomerCode varchar(20) NOT NULL,
    CONSTRAINT PK_Customer PRIMARY KEY CLUSTERED (CustomerId),
    CONSTRAINT UQ_Customer_CustomerCode UNIQUE NONCLUSTERED (CustomerCode),
    CONSTRAINT CK_Customer_Status CHECK (Status IN ('Active','Inactive'))
);
GO

/* INCLUDE order differs but should canonicalize as equivalent. */
CREATE INDEX IX_Customer_Status_CreatedAt
    ON dbo.Customer (Status ASC, CreatedAt DESC)
    INCLUDE (DisplayName, CustomerCode);
GO

CREATE TABLE dbo.CustomerNote
(
    NoteId int NOT NULL,
    CustomerId int NOT NULL,
    NoteText nvarchar(1000) NULL,
    CONSTRAINT PK_CustomerNote PRIMARY KEY (CustomerId, NoteId),
    CONSTRAINT FK_CustomerNote_Customer
        FOREIGN KEY (CustomerId) REFERENCES dbo.Customer(CustomerId)
        ON DELETE CASCADE
);
GO
