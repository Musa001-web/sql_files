

ALTER PROCEDURE [dbo].[up_generate_account_no_New] 
    @Utid VARCHAR(6), 
    @BU VARCHAR(5), 
    @DssId VARCHAR(50), 
    @AssetId VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @series VARCHAR(3),
        @check INT,
        @checkdigit INT, 
        @iSeries INT,
        @Accountnumber VARCHAR(24), 
        @AccountTemp VARCHAR(24), 
        @AccountPart VARCHAR(24), 
        @Book VARCHAR(20), 
        @RandomTwoDigit VARCHAR(2), 
        @ErrMessage VARCHAR(200),
        @ErrorCode INT,
        @DbName VARCHAR(50),
		@UndertakeRowguid UNIQUEIDENTIFIER,
		@CustAccGenRowguid UNIQUEIDENTIFIER,
        @LinkServerIp VARCHAR(50),
		@SQL NVARCHAR(MAX) 

    -- Input validation
    IF NOT EXISTS (
        SELECT 1 
        FROM DistributionSubStation 
        WHERE DistributionID = @DssId AND BUID = @BU
    )
    BEGIN
        SET @ErrMessage = 'Invalid Distribution ID "' + @DssId + '" for the specified Business Unit "' + @BU + '".'
        SET @ErrorCode = 1001
        GOTO OutputResult
    END

    IF NOT EXISTS (
        SELECT 1 
        FROM DistributionSubStation 
        WHERE FeederID = @AssetId AND BUID = @BU AND DistributionID = @DssId
    )
    BEGIN
        SET @ErrMessage = 'Invalid Feeder ID: "' + @AssetId + '" not found under Distribution ID "' + @DssId + '" and Business Hub "' + @BU + '".'
        SET @ErrorCode = 1002
        GOTO OutputResult
    END

    IF NOT EXISTS (
        SELECT 1 
        FROM Undertaking
        WHERE UTID = @Utid AND BUID = @BU  
    )
    BEGIN
        SET @ErrMessage = 'The specified Undertaking ID "' + @Utid + '" does not exist for the provided Business Unit "' + @BU + '".'
        SET @ErrorCode = 1003
        GOTO OutputResult
    END

    SET @RandomTwoDigit = RIGHT('0' + CAST(CAST(RAND() * 99 + 1 AS INT) AS VARCHAR(2)), 2)
    SET @Book = @Utid + '/' + @RandomTwoDigit

	SET @UndertakeRowguid = NEWID();
	SET @CustAccGenRowguid = NEWID();

	BEGIN TRY

    -- Get linked server info
    SELECT 
        @LinkServerIp = LinkServerIP, 
        @DbName = DBname 
    FROM LinkServerInfo 
    WHERE BUID = @BU;

	BEGIN TRANSACTION
        
        -- Lock and get last used serial
        SELECT TOP 1 @series = SerialNo 
        FROM CustomerAccountNoGenerated WITH (UPDLOCK, HOLDLOCK)
        WHERE BookNo = @Book AND buid = @BU
        ORDER BY SerialNo DESC

        IF @series IS NULL
            SET @series = '001'


        -- Ensure UndertakingBookNumber exists
        IF NOT EXISTS (SELECT 1 FROM UndertakingBookNumber WHERE Booknumber = @Book)
        BEGIN
            INSERT INTO UndertakingBookNumber (
                Booknumber, UTID, TransID, billingefficiency,
                energyusededitable, isMD, buid, rowguid
            )
            VALUES (@Book, @Utid, @Utid, 78.0, 0, 0, @BU, @UndertakeRowguid)

          
        END

        -- Handle serial overflow
        IF @series = '999'
        BEGIN
            SELECT TOP 1 @series = RIGHT('000' + CAST(num AS VARCHAR(3)), 3)
            FROM (
                SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS num
                FROM master.dbo.spt_values
                WHERE type = 'P' AND number < 1000
            ) AS T
            WHERE num NOT IN (
                SELECT CONVERT(INT, SerialNo)
                FROM CustomerAccountNoGenerated WITH (NOLOCK)
                WHERE BookNo = @Book AND buid = @BU
            )
            ORDER BY num
        END
        ELSE
        BEGIN
            SET @iSeries = CONVERT(INT, @series)
            IF @iSeries >= 999
            BEGIN
                SET @ErrMessage = 'Maximum account numbers reached for this book.'
                SET @ErrorCode = 1004
                IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
                GOTO OutputResult
            END
            SET @iSeries = @iSeries + 1
            SET @series = RIGHT('000' + CAST(@iSeries AS VARCHAR(3)), 3)
        END

        -- Build and validate account number
        SET @AccountPart = @Book + '/' + @series
        SET @AccountTemp = SUBSTRING(@AccountPart, 1, 2) + SUBSTRING(@AccountPart, 4, 2) +
                           SUBSTRING(@AccountPart, 7, 2) + SUBSTRING(@AccountPart, 10, 3)

        SET @check = 0
        DECLARE @i INT = 0
        WHILE @i < LEN(@AccountTemp)
        BEGIN
            SET @i = @i + 1
            SET @check = @check + CONVERT(INT, SUBSTRING(@AccountTemp, @i, 1)) * @i
        END

        SET @checkdigit = @check % 10
        SET @Accountnumber = @AccountPart + CONVERT(VARCHAR(1), @checkdigit) + '-01'

        -- Final uniqueness check before insert
        IF EXISTS (
            SELECT 1 FROM CustomerAccountNoGenerated 
            WHERE AccountNo = @Accountnumber
        )
        BEGIN
            SET @ErrMessage = 'Duplicate Account Number. Retry.'
            SET @ErrorCode = 1005
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
            GOTO OutputResult
        END

        -- Insert locally
        INSERT INTO CustomerAccountNoGenerated (
            BookNo, SerialNo, AccountNo, DateGenerated,
            Status, BUID,rowguid, Utid, DssId, AssetId
        )
        VALUES (
            @Book, @series, @Accountnumber, GETDATE(),
            0, @BU, @CustAccGenRowguid, @Utid, @DssId, @AssetId
        )

		COMMIT TRANSACTION

    BEGIN TRY
        
		SET @SQL = N'
            IF NOT EXISTS (SELECT 1 FROM [' + @LinkServerIp + '].[' + @DbName + '].[dbo].UndertakingBookNumber 
                          WHERE Booknumber = @Book AND buid = @BU)
            BEGIN
                INSERT INTO [' + @LinkServerIp + '].[' + @DbName + '].[dbo].UndertakingBookNumber (
                    Booknumber, UTID, TransID, billingefficiency,
                    energyusededitable, isMD, buid, rowguid
                )
                VALUES (@Book, @Utid, @Utid, 78.0, 0, 0, @BU, @UndertakeRowguid)
            END'

        EXEC sp_executesql @SQL, 
            N'@Book VARCHAR(20), @Utid VARCHAR(6), @BU VARCHAR(5), @UndertakeRowguid UNIQUEIDENTIFIER', 
            @Book, @Utid, @BU, @UndertakeRowguid

        -- Insert to remote CustomerAccountNoGenerated
        SET @SQL = N'
            INSERT INTO [' + @LinkServerIp + '].[' + @DbName + '].[dbo].CustomerAccountNoGenerated (
                BookNo, SerialNo, AccountNo, DateGenerated,
                Status, BUID, rowguid, Utid, DssId, AssetId
            )
            VALUES (
                @Book, @series, @Accountnumber, GETDATE(),
                0, @BU, @CustAccGenRowguid, @Utid, @DssId, @AssetId
            )'

        EXEC sp_executesql @SQL, 
            N'@Book VARCHAR(20), @series VARCHAR(3), @Accountnumber VARCHAR(24), @BU VARCHAR(5), 
              @Utid VARCHAR(6), @DssId VARCHAR(50), @AssetId VARCHAR(50), @CustAccGenRowguid UNIQUEIDENTIFIER', 
            @Book, @series, @Accountnumber, @BU, @Utid, @DssId, @AssetId, @CustAccGenRowguid


        SET @ErrMessage = 'Account number generated successfully! Please obtain supervisor approval to finalize customer registration.'
        SET @ErrorCode = 0

    END TRY
	BEGIN CATCH
        -- Log remote error but don't fail the operation
        SET @ErrMessage = 'Account generated locally but remote sync failed: ' + ERROR_MESSAGE()
        SET @ErrorCode = 1006
    END CATCH
	END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SET @ErrMessage = ERROR_MESSAGE()
        SET @ErrorCode = ERROR_NUMBER()
    END CATCH

OutputResult:
    SELECT 
        @Accountnumber AS AccountNumber, 
        @ErrorCode AS Code, 
        @ErrMessage AS Message 
END
GO
