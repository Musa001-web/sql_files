

ALTER PROCEDURE [dbo].[up_generate_account_no_New] 
	-- Add the parameters for the stored procedure here
	@Utid Varchar(6), @BU Varchar(10), @DssId Varchar(25), @AssetId Varchar(25)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here
Declare @series varchar(3),@check int,@checkdigit int, @iSeries int
Declare @Accountnumber Varchar(24), @AccountTemp Varchar(24), @AccountPart varchar(24), @Book Varchar(20), @RandomTwoDigit VARCHAR(2), @ErrMessage Varchar(200)

IF NOT EXISTS (
	SELECT 1 
	FROM DistributionSubStation 
	WHERE DistributionID = @DssId AND BUID = @BU
)
BEGIN
	SET @ErrMessage = 'Invalid Distribution ID: "' + @DssId + '" does not exist for Business Hub "' + @BU + '".'
	SET @Accountnumber = -1
END

IF NOT EXISTS (
	SELECT 1 
	FROM DistributionSubStation 
	WHERE FeederID = @AssetId AND BUID = @BU AND DistributionID = @DssId
)
BEGIN
	SET @ErrMessage = 'Invalid Feeder ID: "' + @AssetId + '" not found under Distribution ID "' + @DssId + '" and Business Hub "' + @BU + '".'
	SET @Accountnumber = -1
END

IF NOT EXISTS (
	SELECT 1 
	FROM Undertaking
	WHERE UTID = @Utid AND BUID = @BU  
)
BEGIN
	SET @ErrMessage = 'The specified Undertaking ID "' + @Utid + '" does not exist for the provided Business Unit "' + @BU + '".'
	SET @Accountnumber = -1
END


    SET @RandomTwoDigit = RIGHT('0' + CAST(CAST(RAND() * 99 + 1 AS INT) AS VARCHAR(2)), 2)

	SET @Book = @Utid + '/'+ @RandomTwoDigit

--Set @series = (Select Top 1 ISNULL(SerialNo, '000') from CustomerAccountNoGenerated 
--				where BookNo =@Book And buid = @BU
--				ORDER BY SerialNo DESC)

Select Top 1 @series = SerialNo from CustomerAccountNoGenerated 
				where BookNo =@Book And buid = @BU
				ORDER BY SerialNo DESC

IF @series Is Null
	Set @series = '001'

IF NOT EXISTS (
	SELECT 1 
	FROM UndertakingBookNumber 
	WHERE Booknumber = @Book
)
BEGIN
	INSERT INTO UndertakingBookNumber (
		Booknumber,
		UTID,
		TransID,
		billingefficiency,
		energyusededitable,
		isMD,
		buid,
		rowguid
)
	Values(@Book, @Utid, @Utid, 78.0, 0, 0, @BU, NEWID())
End
				
IF @series = '999'
BEGIN
	SELECT TOP (1) @series = CONVERT(varchar(3), num-1) from Numbers
	where num not in (select CONVERT(INT, SerialNo) FROM CustomerAccountNoGenerated 
	where BookNo =@Book And buid = @BU)
END				

--SET @series = '999'	
IF @series <= '998'	
BEGIN


	SET @iSeries = CONVERT(int, @series)
	SET @iSeries = @iSeries + 1
	SET @series = CONVERT(varchar(3), @iSeries)
	SET @series = RIGHT('000'+CAST(@series AS VARCHAR(3)),3)
	SET @AccountPart = @Book+'/'+@series			--19/25/02/915
	SET @AccountTemp = SUBSTRING(@AccountPart, 1, 2) + SUBSTRING(@AccountPart, 4, 2)
						+ SUBSTRING(@AccountPart, 7, 2) + SUBSTRING(@AccountPart, 10, 3)
						

	declare @i int
	select @i = 0
	set @check = 0
	while @i < len(@AccountTemp)
	begin
		select @i = @i + 1

		select @check = @check + CONVERT(INT, substring(@AccountTemp, @i, 1)) * @i
	end

	SET @checkdigit = @check % 10

	SET @Accountnumber = @AccountPart + CONVERT(varchar(1), @checkdigit)+ '-01'

	IF LEN(@Accountnumber) = 16
	BEGIN
		INSERT INTO CustomerAccountNoGenerated
		(BookNo, SerialNo, AccountNo, DateGenerated, Status, BUID, Utid, DssId, AssetId)
		VALUES (@Book, @series, @Accountnumber, GETDATE(), 1, @BU, @Utid, @DssId, @AssetId)

		Set @ErrMessage= 'New Account Number Generated Successfully'
	END
	ELSE
		SET @Accountnumber = -1

END
ELSE
	SET @Accountnumber = -1
	
	--Output
	SELECT @Accountnumber As AccountNumber, @ErrMessage As ErrorMessage
END

GO