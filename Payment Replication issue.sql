


select * from CustomerNew
where AccountNo NOT in
(select AccountNo from [192.168.15.90].[EMS_IJEUN].[dbo].[CustomerNew] where BUID= '15A')
AND BUID= '15A'


--[dbo].[up_manual_payment_replication_job]
EXEC [dbo].[up_manual_payment_replication] '15A'


SELECT * FROM [dbo].[PaymentTransaction]
	  where transID not in (Select transid from [192.168.15.90].[EMS_IJEUN].[dbo].[PaymentTransaction])
	  and TransactionBusinessUnit COLLATE Latin1_General_CI_AS = '15A'
	  and AccountNo COLLATE Latin1_General_CI_AS in (Select AccountNo from [192.168.15.90].[EMS_IJEUN].[dbo].[CustomerNew])
	  AND transref COLLATE Latin1_General_CI_AS NOT IN (Select transref from [192.168.15.90].[EMS_IJEUN].[dbo].[PaymentTransaction])


SELECT * FROM UserInfo
WHERE OperatorId IN (209,1594)


SELECT * FROM BusinessUnit

SELECT DISTINCT(OperatorID) FROM [dbo].[Payments]
	where PaymentId not in (Select PaymentID from [192.168.15.90].[EMS_IJEUN].[dbo].[Payments])
	and BusinessUnit COLLATE Latin1_General_CI_AS = '15A'
	and AccountNo COLLATE Latin1_General_CI_AS in (Select AccountNo from  [192.168.15.90].[EMS_IJEUN].[dbo].[CustomerNew])
	and PaymentTransactionId in (Select transid from [192.168.15.90].[EMS_IJEUN].[dbo]. [PaymentTransaction])




