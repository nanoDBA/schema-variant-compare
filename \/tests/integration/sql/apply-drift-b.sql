USE SchemaCompareTest;
GO

/* Intentional drift cases. */
DROP INDEX IX_Customer_Status_CreatedAt ON dbo.Customer;
GO
CREATE INDEX IX_Customer_Status_CreatedAt
    ON dbo.Customer (CreatedAt DESC, Status ASC)
    INCLUDE (CustomerCode, DisplayName);
GO

ALTER TABLE dbo.Customer ALTER COLUMN DisplayName nvarchar(320) NULL;
GO

ALTER TABLE dbo.CustomerNote DROP CONSTRAINT FK_CustomerNote_Customer;
GO
ALTER TABLE dbo.CustomerNote
ADD CONSTRAINT FK_CustomerNote_Customer
    FOREIGN KEY (CustomerId) REFERENCES dbo.Customer(CustomerId)
    ON DELETE NO ACTION;
GO
