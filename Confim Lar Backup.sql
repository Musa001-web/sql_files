
/****** Object:  StoredProcedure [dbo].[up_confirmLAR]    Script Date: 7/25/2024 4:52:49 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[up_confirmLAR_25072024] @AccountNo Varchar(26),@Value int,@ConfirmBy Varchar(50)

As 
	Declare @billingperiod int,
			@lastactualreadingdate DateTime,
			@presentreadingdate DateTime,
			@lastreadingbillingperiod int ,
			@previousreadingKWH int,
			@presentreadingKWH int,
			@meterreadingsremark int,
			@validreading bit,
			@operator varchar(50),
			@buid varchar(10)
	Declare @Error int,@ErrorMSG Varchar(200)
BEGIN TRY
	
	
	 IF @Value = 1 
		BEGIN
			Select @billingperiod =BillingPeriod,
			@lastactualreadingdate =lastactualreadingdate,
			@presentreadingdate =presentreadingdate,
			@lastreadingbillingperiod =lastreadingbillingperiod ,
			@previousreadingKWH =previousreadingKWH,
			@presentreadingKWH =presentreadingKWH,
			@meterreadingsremark =meterreadingsremark,
			@validreading =validreading,
			@operator= operator,
			@buid  = buid
			--@operatorEdits=ISNULL(operatorEdits, @ConfirmBy),@operatorEdit=ISNULL(operatorEdit, @ConfirmBy)
			From MeterReadingSheet_Confirm
			Where accountnumber = @AccountNo
						
				UPDATE MeterReadingSheet 
				SET presentreadingKWH=@presentreadingKWH,validreading=1,meterreadingsremark=-1,
				presentreadingdate=DATEADD(MONTH, -1, GETDATE())
				WHERE accountnumber = @AccountNo and billingperiod = @lastreadingbillingperiod


				UPDATE MeterReadingSheet 
				SET previousreadingKWH=@previousreadingKWH,lastreadingbillingperiod=@lastreadingbillingperiod,
				lastactualreadingdate=DATEADD(MONTH, -1, GETDATE())
				WHERE accountnumber = @AccountNo and billingperiod = dbo.udf_get_billingperiod()
				 
				 SET @lastreadingbillingperiod = NULL

				SELECT @lastreadingbillingperiod=MAX(billingperiod)
				FROM Consumption
				WHERE AccountNo = @AccountNo AND consumptionconfirmed =1

				if (@lastreadingbillingperiod is not null)
				BEGIN
					DELETE FROM  Consumption
					WHERE AccountNo = @AccountNo AND billingperiod>@lastreadingbillingperiod
	
					UPDATE Consumption
					SET presentreadingkwh = @presentreadingKWH ,ReadMode='R'
					WHERE AccountNo = @AccountNo AND billingperiod=@lastreadingbillingperiod
		
	
	
				END


				INSERT INTO dbo.AuditLog (Module,TableName,KeyValue,FieldName,ChangeFrom,ChangeTo,DateTime,Operator,BUID)
				values (5,'MeterReadingSheet',@AccountNo,'Reading Adjustment',@presentreadingKWH,@previousreadingKWH,getdate(),@operator ,@buid)

				

				SELECT 1 as [ErrorCode], 'Meter Reading Adjusted ' as [ErrorMessage]
				 
				 If @@ROWCOUNT >0 AND @@ERROR = 0
						Begin 
							
							
							Delete From MeterReadingSheet_Confirm
							Where accountnumber = @AccountNo
							
							Delete from AuditLogConfirm where KeyValue = @AccountNo and TableName= 'MeterReadingSheet'
							
							Set @Error = 1
							Set @ErrorMSG = 'LAR with AccountNo: '+@AccountNo+' Was Updated Successfully'
							Raiserror (@ErrorMSG,16,1)
						End
						else
						begin
							Set @Error = 0
							Set @ErrorMSG = 'LAR with AccountNo: '+@AccountNo+' NOT found!!!..'
							Raiserror (@ErrorMSG,16,1)
						end
				 
			END
	ELSE IF @Value = 2 
		BEGIN
				Delete From MeterReadingSheet_Confirm
				Where accountnumber = @AccountNo
							
				Delete from AuditLogConfirm where KeyValue = @AccountNo and TableName= 'MeterReadingSheet'
				
				Set @Error = 1
				Set @ErrorMSG = 'LAR with AccountNo: '+@AccountNo+' Was Discarded'
				Raiserror (@ErrorMSG,16,1)
			END
	
END TRY

BEGIN CATCH
	Select @Error As ErrorCode, ERROR_MESSAGE() AS ErrorMessage
END CATCH