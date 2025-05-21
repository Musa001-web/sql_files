

Alter PROCEDURE Up_Get_UnusedAvailableAccountNoGenerated
    @Buid VARCHAR(10)
AS
BEGIN
    DECLARE @ErrMessage VARCHAR(200)

    IF EXISTS (
        SELECT 1
        FROM CustomerAccountNoGenerated
        WHERE Status = 0 AND BUID = @Buid
    )
    BEGIN
        SELECT AccountNo
        FROM CustomerAccountNoGenerated
        WHERE Status = 0 AND BUID = @Buid
    END
    ELSE
    BEGIN
        SET @ErrMessage = 'No Available Unused Account Number for the Provided Business Unit'
        RAISERROR(@ErrMessage, 16, 1)
    END
END

