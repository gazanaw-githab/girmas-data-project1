Use BOfA_customer
Go

IF OBJECT_ID('basp_Campaign_SavingToCredit', 'P') IS NOT NULL
			DROP PROCEDURE basp_Campaign_SavingToCredit
GO

CREATE PROCEDURE basp_Campaign_SavingToCredit

		@Run_Date DATE = NULL

AS
BEGIN

/**** 
Procedure Name: basp_Campaign_SavingToCredit

Purpose: Loading lead customers to Campaign List and Campaign Histiry tables.

Description: Clients that have Saving Account but no Credit Card Account with the bank are encouraged to 
			 open Credit Card  Account throgh a campaign. The objective of this stored procedure is to 
			 generate leads that meet the requirements BRD CaseID 5001.

Execusion Time: Less than a minute.

Revision History
Date				Intials					Description
==============		================		================
7/24/2025			GA						Initial Version
7/27/2025			GA						Added Batch Log component to the procedure
7/28/2025			GA						Added error handling and transaction control to the proc.


****/

IF @Run_Date IS NULL
	SET @Run_Date = CAST(GETDATE() AS DATE)

----Declaring variables

DECLARE
	 
	 @l_BatchID INT
	,@l_ProcedureName VARCHAR (50)
	--,@l_MessageType CHAR (1)
	,@l_Message VARCHAR (4000)
	,@l_ErrorSeverity VARCHAR (20)
	,@l_ErrorLine INT
	,@l_ErrorMessage VARCHAR (255)

	
	,@CampaignName VARCHAR(50)
	,@ListDate DATE
	,@SavingBalance DECIMAL (10,2)
	,@Age INT


SET @l_ProcedureName = 'basp_Campaign_SavingToCredit'
SET @l_Message = 'Starting Execusion'

EXEC @l_BatchID =  [dbo].[basp_AllocateBatchID]
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'I' , @l_Message 

----Setting intial values to the variables

SET @CampaignName = 'Saving to Credit Account'
SET @ListDate = @Run_Date

SET @SavingBalance = (
						SELECT Code_Value 
						FROM [dbo].[ref_CpgnRules]
						WHERE ProcedureName = 'basp_Campaign_SavingToCredit'
						AND CampaignGroup = 'DM'
							AND Code_ID = 'Minimum Saving'
							AND Active = 'Y'
					)

SET @Age =  (
				SELECT Code_Value 
				FROM [dbo].[ref_CpgnRules]
				WHERE ProcedureName = 'basp_Campaign_SavingToCredit'
				AND CampaignGroup = 'DM'
				AND Code_ID = 'Minimum Age'
				AND Active = 'Y'
			)

----Creating the Starting Population

BEGIN TRY

IF OBJECT_ID ('tempdb..#Pop') IS NOT NULL
			DROP TABLE #Pop

CREATE TABLE #Pop
(
	 [AcctNo] varchar(25) NULL
	,CampaignName varchar (50)	
	,[First_Name] varchar (50) NULL
	,[Last_Name] varchar (50) NULL
	,[Scrub] varchar(100) NULL
	,[Email_Address] varchar (50) NULL
	,[Detail1] datetime NULL			----DOB
	,[Detail2] decimal (10, 2) NULL					----Age of Saving account
	,[Detail3] decimal (10, 2) NULL		----Saving Balance
	,[Address1] varchar(50) NULL
	,[Address2] varchar (50) NULL
	,[AddressCity] varchar (25) NULL
	,[AddressState] varchar (5) NULL
	,[AddressZip] varchar (10) NULL
	,[DateOfBirth] datetime NULL
	,[OpenDate] datetime NULL
	,[Assets] decimal (10, 2) NULL
	,[Channel] varchar (50) NULL
)

SET @l_Message = '#Pop table is successfully created'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

INSERT INTO  #Pop 
(
	 [AcctNo]
	,[CampaignName]
	,[First_Name] 
	,[Last_Name]
	,[Scrub]
	,[Email_Address]
	,[Detail1]
	,[Detail2]
	,[Detail3]
	,[Address1]
	,[Address2]
	,[AddressCity]
	,[AddressZip]
	,[Assets]
	,[Channel]
)

SELECT 
	 AD.[AcctNo]
	,@CampaignName 
	,AP.[First_Name] 
	,AP.[Last_Name]
	,'Available'
	,AP.[email]
	,AP.[DateOFBirth]	--Detail1
	,DATEDIFF(DAY, AP.OpenDate, GETDATE())/365.25 ----Deatil2 Age of Saving Account
	,AF.[Assets]		--These Assets are considered as  the Saving Account Balance as Detail3
	,AP.[AddressLine1]
	,AP.[AddressLine12]
	,AP.[AddressCity]
	,AP.[AddressZipCd]
	,AF.[Assets]
	,AP.[Channel]
FROM [BOfA_customer].[dbo].[Accounts_Profile] AP
JOIN [dbo].[Accounts_Financial] AF ON 
AP.[AcctNo]= AF.[AcctNo]
JOIN [dbo].[Accounts_Date] AD ON
AP.[AcctNo]= AD.[AcctNo]
WHERE AP.[Channel] IN ('Saving') AND AP.[Channel]  NOT IN ('Credit Card')  /* Clients who have 
a saving account but not a credit card account requirement*/

SET @l_Message = 'Inserted ' + Cast(@@RowCount AS Varchar) + ' clients into the #Pop table'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

--------------------------Applying Exclusions Rules----------------------------------------------

---Primary account holder is deceased (DSCD)

Update p
	SET Scrub = 'DSCD'
	FROM #Pop p
	WHERE Scrub = 'Available' AND
	[AcctNo] IN (SELECT [AcctNo] FROM [dbo].[BOfA_DSCD_Customers])

SET @l_Message = 'Updated Scrub column with ' + Cast(@@RowCount AS Varchar) + ' deceased clients'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

----Money Laundering Alert present (MLA)

UPDATE p
	SET Scrub = 'MLA'
	FROM #Pop p
	WHERE Scrub = 'Available' AND
	[AcctNo] IN (SELECT [AcctNo] FROM [dbo].[BOfA_AML_Customers])

SET @l_Message = 'Updated Scrub column with ' + Cast(@@RowCount AS Varchar) + ' MLA clients'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

---HH has a zip code in a FEMA disaster area 

UPDATE p
	SET Scrub = 'HazardHittedArea'
	FROM #Pop p
	WHERE Scrub = 'Available' AND
	[AddressZip] IN (SELECT [HZIP] FROM [dbo].[BOfA_HZIP])

SET @l_Message = 'Updated Scrub column with ' + Cast(@@RowCount AS Varchar) + ' HH in a FEMA zipcode clients'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

---Accounts that have less than or equal to 1000 in saving 

UPDATE p
	SET Scrub = 'Less  than or Equal to 1000'
	FROM #Pop p
	WHERE Scrub = 'Available' AND
	[Assets] <= @SavingBalance

SET @l_Message = 'Updated Scrub column with ' + Cast(@@RowCount AS Varchar) + ' =< 1000 saving balance clients'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

---Clients that are younger than 25 years

UPDATE p
	SET Scrub = 'Younger than 25 years'
    FROM #Pop p
	WHERE Scrub = 'Available' AND
	DATEDIFF(DAY, [Detail1], GETDATE())/365.25 < @Age

SET @l_Message = 'Updated Scrub column with ' + Cast(@@RowCount AS Varchar) + ' =< 25 years of age clients'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 


--------------------------Loading to Campaign List Table-------------------------------------------------

			BEGIN TRAN

----DELETE to allow rerun and avoid similar data population in a same day

DELETE FROM [dbo].[BoFA_CampaignList]
WHERE [Campaign_Name] = @Campaignname AND 
[Listdate] = @ListDate

INSERT INTO [dbo].[BoFA_CampaignList] 
(
	 ListDate
	,[AcctNo]
	,[Campaign_Name]
	,[Detail1]
	,[Detail2]
	,[Detail3]
	,[Scrub]
	,[Email_Address]
	,[First_Name]
	,[Last_Name]
	,[Address1]
	,[Address2]
	,[AddressCity]
	,[AddressState]
	,[AddressZip]
)
 
SELECT 
	 @ListDate
	,[AcctNo]
	,@CampaignName 
	,[Detail1]
	,[Detail2]
	,[Detail3]
	,[Scrub]
	,[Email_Address]
	,[First_Name]
	,[Last_Name]
	,[Address1]
	,[Address2]
	,[AddressCity]
	,[AddressState]
	,[AddressZip]
FROM #Pop
WHERE Scrub Not In ('Less  than or Equal to 1000','DSCD','HazardHittedArea','MLA',
'Younger than 25 years') /**Campaign List with the BRD requirements **/

SET @l_Message = 'Inserted ' + Cast(@@RowCount AS Varchar) + ' clients into Campaign List table '
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

--------------------------Loading to Campaign History Table-------------------------------------------------

----DELETE to allow rerun and avoid similar data population in a same day

DELETE FROM [dbo].[BOfA_CPGN_HISTORY]
WHERE [Campaignname] = @Campaignname AND 
[Listdate] = @ListDate


INSERT INTO [dbo].[BOfA_CPGN_HISTORY] 
(
	 ListDate
	,[Campaignname]
	,[Channel]
	,[Acctno]
	,[EmailAddress]
	,[FirstName]
	,[LastName]
	,[Address1]
	,[Address2]
	,[City]
	,[State]
	,[Zip]
	,[Detail1]
	,[Detail2]
	,[Detail3]
	,[Scrub]
) 

Select 
	 @ListDate
	,@CampaignName 
	,'DM'
	,P.[AcctNo]
	,P.[Email_Address]
	,P.[First_Name]
	,P.[Last_Name]
	,P.[Address1]
	,P.[Address2]
	,P.[AddressCity]
	,P.[AddressState]
	,P.[AddressZip]
	,P.[Detail1]
	,P.[Detail2]
	,P.[Detail3]
	,P.[Scrub]
FROM #Pop p

SET @l_Message = 'Inserted ' + Cast(@@RowCount AS Varchar) + ' clients into Campaign History table'
EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'S' , @l_Message 

			COMMIT TRAN

				PRINT 'Pocedore '+ @CampaignName + ' Completed Successfully on '+ Cast(@ListDate AS Varchar)

				SET @l_Message = 'Procedure Successfully Completed'
				EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'E' , @l_Message 

				IF OBJECT_ID ('tempdb..#Pop') IS NOT NULL DROP TABLE #Pop
END TRY

		BEGIN CATCH
			
			IF @@TRANCOUNT > 0
			ROLLBACK TRAN

			PRINT 'Error Excuting Pocedore '+ @CampaignName  +  Cast(@ListDate AS Varchar)

			SELECT @l_ErrorSeverity = CAST(ERROR_SEVERITY() AS VARCHAR)
					,@l_ErrorLIne = ERROR_LINE()
					,@l_ErrorMessage = ERROR_MESSAGE()

			SET @l_Message = @l_ErrorMessage + ' on Line ' + CAST(@l_ErrorLIne AS VARCHAR)
			EXEC  [dbo].[basp_LogMessage] @l_BatchID, @l_ProcedureName, 'E' , @l_Message , @l_ErrorSeverity

			IF OBJECT_ID ('tempdb..#Pop') IS NOT NULL DROP TABLE #Pop

		END CATCH
END