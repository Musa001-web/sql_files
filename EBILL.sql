--Zone (All at once)
INSERT INTO EmailLog_BAK
SELECT * FROM EmailLog
GO

SELECT * FROM BillingPeriod_BAK

DELETE EmailLog
GO

INSERT INTO FeederEnergyDetails_bak
SELECT * FROM FeederEnergyDetails
GO

DELETE FeederEnergyDetails
GO

INSERT INTO BillingPeriod_BAK
SELECT * FROM BillingPeriod
GO

DELETE FROM BillingPeriod
GO


----jebba

--SELECT * FROM LinkServerInfo where LinkServerIP = '192.168.15.90' ORDER BY LinkServerIP

----[EMS_JEBBA] BHUB
--INSERT INTO BillingPeriod(billingperiodid, billingperiodmonth, [billingperiodmonthname], [billingperiodmonthnameshort], [billingperiodyear], [startdate], [enddate], [activebillingperiod], [billduedate], [BUID],[highfactor], [lowfactor])
--SELECT billingperiodid, billingperiodmonth, [billingperiodmonthname], [billingperiodmonthnameshort], [billingperiodyear], [startdate], [enddate], 1, [billduedate], [BUID],[highfactor], [lowfactor]
--from [192.168.15.80].[EMS_JEBBA].dbo.BillingPeriod
--where billingperiodid = (SELECT TOP 1 billingperiodid-1 FROM [192.168.15.80].[EMS_JEBBA].dbo.BillingPeriod WHERE activebillingperiod = 1)

----[EMS_JEBBA] BHUB
--INSERT INTO FeederEnergyDetails(BillingPeriod, Feeder, DateEntered, buid, CapUnit)
--SELECT BillingPeriod, Feeder, DateEntered, buid, CapUnit
--FROM [192.168.15.80].EMS_JEBBA.dbo.FeederEnergyDetails 
--WHERE BILLINGPERIOD = (SELECT TOP 1 billingperiodid-1 FROM [192.168.15.80].EMS_JEBBA.dbo.BillingPeriod WHERE activebillingperiod = 1)




DECLARE @DBname VARCHAR(90)
DECLARE @LinkserverIP VARCHAR(90)
DECLARE @SQL VARCHAR(MAX)



DECLARE DB_CURSOR CURSOR FOR
SELECT DBname, LinkserverIP FROM LinkServerInfo

OPEN DB_CURSOR

FETCH NEXT FROM DB_CURSOR INTO @DBname, @LinkServerIP

WHILE @@FETCH_STATUS = 0
BEGIN
		
	begin try
		SET @SQL = 'INSERT INTO BillingPeriod(billingperiodid, billingperiodmonth, [billingperiodmonthname], [billingperiodmonthnameshort], 
		[billingperiodyear], [startdate], [enddate], [activebillingperiod], [billduedate], [BUID],[highfactor], [lowfactor])
		SELECT billingperiodid, billingperiodmonth, [billingperiodmonthname], [billingperiodmonthnameshort], [billingperiodyear], 
		[startdate], [enddate], 1, [billduedate], [BUID],[highfactor], [lowfactor] 
		from '+ QUOTENAME(@LinkServerIP)+'.' + QUOTENAME(@DBname) + '.dbo.BillingPeriod
		where billingperiodid = (SELECT TOP 1 billingperiodid-1 
		FROM '+ QUOTENAME(@LinkServerIP)+'.' + QUOTENAME(@DBname) + '.dbo.BillingPeriod WHERE activebillingperiod = 1)'
		--PRINT @SQL
		EXEC (@SQL)
		PRINT QUOTENAME(@DBname)+' BILLINGPERIOD INSERTED SUCCESSFULLY'
	

		SET @SQL = 'INSERT INTO FeederEnergyDetails(BillingPeriod, Feeder, DateEntered, buid, CapUnit)
		SELECT BillingPeriod, Feeder, DateEntered, buid, CapUnit
		FROM '+ QUOTENAME(@LinkServerIP)+'.' + QUOTENAME(@DBname) + '.dbo.FeederEnergyDetails 
		WHERE BILLINGPERIOD = (SELECT TOP 1 billingperiodid-1 
		FROM '+ QUOTENAME(@LinkServerIP)+'.' + QUOTENAME(@DBname) + '.dbo.BillingPeriod WHERE activebillingperiod = 1) AND BUID is not NULL'
		--PRINT @SQL
		EXEC (@SQL)
		PRINT QUOTENAME(@DBname)+ ' FEEDERENERGY DETAILS INSERTED SUCCESSFUL'

	end try
	begin catch
			
			PRINT 'ERROR_PROCESSING '+ QUOTENAME(@DBname)+ ' BILLINGPERIOD/FEEDERENERGYDETAILS'
			PRINT ERROR_MESSAGE()
	end catch
		

		FETCH NEXT FROM DB_CURSOR INTO @DBname, @LinkServerIP

END

CLOSE DB_CURSOR

DEALLOCATE DB_CURSOR
		

