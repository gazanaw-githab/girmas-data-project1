Insert Into [BOfA_customer].[dbo].[ref_CpgnRules]
 (
 [ProcedureName]
      ,[CampaignGroup]
      ,[Code_ID]
      ,[Code_Value]
      ,[Active]
      ,[CreatedDate]
      ,[UpdateDate]
)
Values (
		'basp_Campaign_SavingToCredit'
		,'DM'
		,'Minimum Saving'
		,1000
		,'Y'
		,GetDate()
		,GetDate()
		)

Insert Into [BOfA_customer].[dbo].[ref_CpgnRules]
 (
 [ProcedureName]
      ,[CampaignGroup]
      ,[Code_ID]
      ,[Code_Value]
      ,[Active]
      ,[CreatedDate]
      ,[UpdateDate]
)
Values (
		'basp_Campaign_SavingToCredit'
		,'DM'
		,'Minimum Age'
		,25
		,'Y'
		,GetDate()
		,GetDate()
		)

