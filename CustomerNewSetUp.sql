
ALTER PROCEDURE Up_InsertCustomerNewSetUp
    @AccountNo               VARCHAR(20),
    @MeterNo                 VARCHAR(20) = NULL,
    @Surname                 VARCHAR(50),
    @FirstName               VARCHAR(25),
    @OtherNames              VARCHAR(50),
    @email                   VARCHAR(50),
    @ServiceAddress1         VARCHAR(200),
    @ServiceAddress2         VARCHAR(200),
    @ServiceAddressCity      VARCHAR(50),
    @ServiceAddressState     VARCHAR(50),
    @TariffID                INT,     
    @ArrearsBalance          DECIMAL(18,2) = 0,
    @Mobile                  VARCHAR(20),
    @GIScoordinate           VARCHAR(20), 
    @BUID                    VARCHAR(5), 
    @DistributionID          VARCHAR(50),
    @AccessGroupName         VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ErrorCode INT = 0, 
        @ErrorMessage VARCHAR(200) = '', 
        @DbName VARCHAR(50), 
        @LinkServerIp VARCHAR(50),
        @UTID VARCHAR(5) = SUBSTRING(@AccountNo,1,5),
        @BookNumber VARCHAR(8) = SUBSTRING(@AccountNo,1,8),
        @TransID VARCHAR(5) = SUBSTRING(@AccountNo,1,5),
        @CustomerID UNIQUEIDENTIFIER = NEWID(),
        @RowGuid UNIQUEIDENTIFIER = NEWID(),
		@AuditRowGuid UNIQUEIDENTIFIER = NEWID(),
        @CurrentDate DATETIME = GETDATE(),
        @RemoteCustomer BIT = 0;

    BEGIN TRY
        -- Get link server information
        SELECT 
            @LinkServerIp = LinkServerIP, 
            @DbName = DBname 
        FROM LinkServerInfo 
        WHERE BUID = @BUID;

        IF @LinkServerIp IS NULL OR @DbName IS NULL
        BEGIN
            SET @ErrorCode = -7;
            SET @ErrorMessage = 'Link server information not found for BUID: ' + @BUID;
            GOTO ErrorHandler;
        END

        -- Check if customer exists on remote server (outside transaction)
        DECLARE @CheckSQL NVARCHAR(MAX) = N'
            SELECT @RemoteCustomer = CASE WHEN EXISTS (
                SELECT 1 FROM [' + @LinkServerIp + '].[' + @DbName + '].[dbo].CustomerNew 
                WHERE AccountNo = @AccountNo AND BUID = @BUID
            ) THEN 1 ELSE 0 END';

        EXEC sp_executesql @CheckSQL, 
            N'@AccountNo VARCHAR(20), @BUID VARCHAR(5), @RemoteCustomer BIT OUTPUT',
            @AccountNo, @BUID, @RemoteCustomer OUTPUT;

        IF @RemoteCustomer = 1
        BEGIN
            SET @ErrorCode = -1;
            SET @ErrorMessage = 'Account Number already assigned to another customer';
            
            -- Update local unused account
            UPDATE CustomerAccountNoGenerated 
            SET Status = 1 
            WHERE AccountNo = @AccountNo AND Status = 0 AND BUID = @BUID;

            -- Update remote unused account (outside transaction)
            DECLARE @UnusedAccountSQL NVARCHAR(MAX) = N'
                UPDATE [' + @LinkServerIp + '].[' + @DbName + '].[dbo].CustomerAccountNoGenerated 
                SET Status = 1 
                WHERE AccountNo = @AccountNo AND Status = 0 AND BUID = @BUID';

            EXEC sp_executesql @UnusedAccountSQL, 
                N'@AccountNo VARCHAR(20), @BUID VARCHAR(5)', 
                @AccountNo, @BUID;

            GOTO ErrorHandler;
        END
        -- Validation checks
        IF NOT EXISTS (SELECT 1 FROM CustomerAccountNoGenerated WHERE AccountNo = @AccountNo AND BUID = @BUID)
        BEGIN
            SET @ErrorCode = -2;
            SET @ErrorMessage = 'The provided account number does not exist or was not generated for the specified business unit.';
            GOTO ErrorHandler;
        END

        IF NOT EXISTS (SELECT 1 FROM DistributionSubStation WHERE DistributionID = @DistributionID)
        BEGIN
            SET @ErrorCode = -3;
            SET @ErrorMessage = 'Invalid DistributionID';
            GOTO ErrorHandler;
        END

        IF NOT EXISTS (SELECT 1 FROM BusinessUnit WHERE BUID = @BUID)
        BEGIN
            SET @ErrorCode = -4;
            SET @ErrorMessage = 'Invalid BUID';
            GOTO ErrorHandler;
        END

        IF NOT EXISTS (SELECT 1 FROM Undertaking WHERE UTID = @UTID AND BUID = @BUID)
        BEGIN
            SET @ErrorCode = -5;
            SET @ErrorMessage = 'Invalid Undertaking for given BUID';
            GOTO ErrorHandler;
        END

        IF NOT EXISTS (SELECT 1 FROM Tariff WHERE TariffID = @TariffID)
        BEGIN
            SET @ErrorCode = -6;
            SET @ErrorMessage = 'Invalid TariffID';
            GOTO ErrorHandler;
        END

        BEGIN TRANSACTION

        -- Insert into local database
        INSERT INTO CustomerNew (
            AccountNo, booknumber, MeterNo, Surname, FirstName, OtherNames,
            Address1, Address2, City, State, email, ServiceAddress1, ServiceAddress2,
            ServiceAddressCity, ServiceAddressState, TariffID, ArrearsBalance, Mobile, 
            Vat, ApplicationDate, GIScoordinate, SetUpDate, ConnectDate, 
            UTID, BUID, TransID, OperatorName, StatusCode, ADC, StoredAverage, IsBulk, DistributionID, 
            NewsetupDate, rowguid, IsCAPMI, operatorEdits, operatorEdit, IsConfirmed, ConfirmBy, DateConfirm, BackBalance, GIS,
            CustomerID
        )
        VALUES (
            @AccountNo, @BookNumber, @MeterNo, @Surname, @FirstName, @OtherNames,
            @ServiceAddress1, @ServiceAddress2, @ServiceAddressCity, @ServiceAddressState, 
            @email, @ServiceAddress1, @ServiceAddress2,
            @ServiceAddressCity, @ServiceAddressState, @TariffID, @ArrearsBalance, @Mobile, 
            1, @CurrentDate, @GIScoordinate, @CurrentDate, @CurrentDate, 
            @UTID, @BUID, @TransID, @AccessGroupName, 'A', 50, 50, 0, @DistributionID, 
            @CurrentDate, @RowGuid, 0, @AccessGroupName, @AccessGroupName, 1, NULL, NULL, 0, NULL,
            @CustomerID
        );

        -- Update local unused account
        UPDATE CustomerAccountNoGenerated 
        SET Status = 1 
        WHERE AccountNo = @AccountNo AND Status = 0 AND BUID = @BUID;

        -- Insert local audit log
        INSERT INTO AuditLog(LogID, Module, TableName, KeyValue, FieldName, ChangeFrom, ChangeTo, DateTime, Operator, BUID, rowguid)
        VALUES(NEWID(), 4, 'CustomerNew', @AccountNo, 'New Setup', NULL, NULL, GETDATE(), @AccessGroupName, @BUID, @AuditRowGuid);

        COMMIT TRANSACTION;

        BEGIN TRY
            -- Insert into remote database
            DECLARE @RemoteSQL NVARCHAR(MAX) = N'
                INSERT INTO [' + @LinkServerIp + '].[' + @DbName + '].[dbo].CustomerNew (
                    AccountNo, booknumber, MeterNo, Surname, FirstName, OtherNames,
                    Address1, Address2, City, State, email, ServiceAddress1, ServiceAddress2,
                    ServiceAddressCity, ServiceAddressState, TariffID, ArrearsBalance, Mobile, 
                    Vat, ApplicationDate, GIScoordinate, SetUpDate, ConnectDate, 
                    UTID, BUID, TransID, OperatorName, StatusCode, ADC, StoredAverage, IsBulk, DistributionID, 
                    NewsetupDate, rowguid, IsCAPMI, operatorEdits, operatorEdit, IsConfirmed, ConfirmBy, DateConfirm, BackBalance, GIS,
                    CustomerID
                )
                VALUES (
                    @AccountNo, @BookNumber, @MeterNo, @Surname, @FirstName, @OtherNames,
                    @ServiceAddress1, @ServiceAddress2, @ServiceAddressCity, @ServiceAddressState, 
                    @email, @ServiceAddress1, @ServiceAddress2,
                    @ServiceAddressCity, @ServiceAddressState, @TariffID, @ArrearsBalance, @Mobile, 
                    1, @CurrentDate, @GIScoordinate, @CurrentDate, @CurrentDate, 
                    @UTID, @BUID, @TransID, @AccessGroupName, ''A'', 50, 50, 0, @DistributionID, 
                    @CurrentDate, @RowGuid, 0, @AccessGroupName, @AccessGroupName, 1, NULL, NULL, 0, NULL,
                    @CustomerID
                )';

            EXEC sp_executesql @RemoteSQL, 
                N'@AccountNo VARCHAR(20), @BookNumber VARCHAR(8), @MeterNo VARCHAR(20), 
                @Surname VARCHAR(50), @FirstName VARCHAR(25), @OtherNames VARCHAR(50),
                @ServiceAddress1 VARCHAR(200), @ServiceAddress2 VARCHAR(200), 
                @ServiceAddressCity VARCHAR(50), @ServiceAddressState VARCHAR(50),
                @email VARCHAR(50), @TariffID INT, @ArrearsBalance DECIMAL(18,2), @Mobile VARCHAR(20), 
                @GIScoordinate VARCHAR(20), @UTID VARCHAR(5), @BUID VARCHAR(5),
                @TransID VARCHAR(5), @AccessGroupName VARCHAR(50), @DistributionID VARCHAR(50),
                @RowGuid UNIQUEIDENTIFIER, @CurrentDate DATETIME, @CustomerID UNIQUEIDENTIFIER',
                @AccountNo, @BookNumber, @MeterNo, @Surname, @FirstName, @OtherNames,
                @ServiceAddress1, @ServiceAddress2, @ServiceAddressCity, @ServiceAddressState,
                @email, @TariffID, @ArrearsBalance, @Mobile, @GIScoordinate, @UTID, @BUID, @TransID,
                @AccessGroupName, @DistributionID, @RowGuid, @CurrentDate, @CustomerID;

            -- Update remote unused account
            DECLARE @UpdateRemoteSQL NVARCHAR(MAX) = N'
                UPDATE [' + @LinkServerIp + '].[' + @DbName + '].[dbo].CustomerAccountNoGenerated 
                SET Status = 1 
                WHERE AccountNo = @AccountNo AND Status = 0 AND BUID = @BUID';

            EXEC sp_executesql @UpdateRemoteSQL, 
                N'@AccountNo VARCHAR(20), @BUID VARCHAR(5)', 
                @AccountNo, @BUID;

            -- Insert remote audit log
            DECLARE @RemoteAuditSQL NVARCHAR(MAX) = N'
                INSERT INTO [' + @LinkServerIp + '].[' + @DbName + '].[dbo].AuditLog (
                    LogID, Module, TableName, KeyValue, FieldName, ChangeFrom, ChangeTo, DateTime, Operator, BUID, rowguid
                )
                VALUES (
                    NEWID(), 4, ''CustomerNew'', @AccountNo, ''New Setup'', NULL, NULL, @CurrentDate, @AccessGroupName, @BUID, @AuditRowGuid
                )';

            EXEC sp_executesql @RemoteAuditSQL,
                N'@AccountNo VARCHAR(20), @CurrentDate DATETIME, @AccessGroupName VARCHAR(50), @BUID VARCHAR(5), @AuditRowGuid UNIQUEIDENTIFIER',
                @AccountNo, @CurrentDate, @AccessGroupName, @BUID, @AuditRowGuid;

        END TRY
        BEGIN CATCH
            
            SET @ErrorCode = -8;
            SET @ErrorMessage = 'Customer created locally but remote synchronization failed: ' + ERROR_MESSAGE();
            GOTO FinalHandler;
        END CATCH

        SET @ErrorCode = 0;
        SET @ErrorMessage = 'Customer registered successfully.';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        IF @ErrorCode = 0 
        BEGIN
            SET @ErrorCode = ERROR_NUMBER();
            SET @ErrorMessage = ERROR_MESSAGE();
        END
    END CATCH

    ErrorHandler:
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

    FinalHandler:
        SELECT @ErrorCode AS ErrorCode, @ErrorMessage AS ErrorMessage;
        RETURN;
END