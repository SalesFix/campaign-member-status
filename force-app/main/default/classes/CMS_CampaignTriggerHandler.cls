/**
 * @description Campaign trigger handler: marks Campaigns of a protected Type and gives new
 * protected Campaigns their configured Campaign Member Statuses.
 * <br>Holds no queries or DML itself; `CampaignMemberService` does the system-level work.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      David Schach
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public inherited sharing class CMS_CampaignTriggerHandler {
	private List<Campaign> newRecords;
	private Map<Id, Campaign> oldRecordsMap;
	private CampaignMemberService cmService;

	/**
	 * @description Constructor used by the Campaign trigger
	 */
	public CMS_CampaignTriggerHandler() {
		this((List<Campaign>) Trigger.new, (Map<Id, Campaign>) Trigger.oldMap);
	}

	/**
	 * @description           Constructor for tests and other trigger frameworks
	 *
	 * @param newRecords      `Trigger.new`
	 * @param oldRecordsMap   `Trigger.oldMap` (null on insert)
	 */
	public CMS_CampaignTriggerHandler(List<Campaign> newRecords, Map<Id, Campaign> oldRecordsMap) {
		this.newRecords = newRecords == null ? new List<Campaign>() : newRecords;
		this.oldRecordsMap = oldRecordsMap == null ? new Map<Id, Campaign>() : oldRecordsMap;
		this.cmService = CampaignMemberService.getInstance();
	}

	/**
	 * @description Flag Campaigns whose Type is protected, and stop users ticking the box themselves.
	 * <br>Clones are re-evaluated from their own Type, because the box is copied from the source
	 * Campaign: a clone of an unprotected Campaign can still need protecting, and a clone whose
	 * Type was changed may no longer be protected.
	 */
	public void beforeInsert() {
		for (Campaign camp : newRecords) {
			Boolean typeIsProtected = cmService.isProtectedType(camp.Type);
			if (camp.isClone()) {
				camp.Protect_Campaign_Member_Statuses__c = typeIsProtected;
				continue;
			}
			if (camp.Protect_Campaign_Member_Statuses__c) {
				camp.addError('Protect_Campaign_Member_Statuses__c', System.Label.CMS_Do_not_check_box_on_Campaign_Create);
				continue;
			}
			camp.Protect_Campaign_Member_Statuses__c = typeIsProtected;
		}
	}

	/**
	 * @description Give new protected Campaigns exactly their configured statuses.
	 * <br>Any Campaign whose statuses can't be set up is rejected with the reason, so it is never
	 * saved with the wrong statuses. Other Campaigns in the same batch are unaffected.
	 */
	public void afterInsert() {
		Map<Id, Campaign> protectedCampaignsById = new Map<Id, Campaign>();
		for (Campaign camp : newRecords) {
			if (camp.Protect_Campaign_Member_Statuses__c) {
				protectedCampaignsById.put(camp.Id, camp);
			}
		}
		if (protectedCampaignsById.isEmpty()) {
			return;
		}

		Map<Id, String> errorsByCampaignId = cmService.applyProtectedStatusesToNewCampaigns(protectedCampaignsById.keySet());
		for (Id campaignId : errorsByCampaignId.keySet()) {
			Campaign camp = protectedCampaignsById.get(campaignId);
			if (camp != null) {
				camp.addError(String.format(System.Label.CMS_Could_Not_Apply_Statuses, new List<Object>{ errorsByCampaignId.get(campaignId) }));
			}
		}
	}

	/**
	 * @description Make sure people aren't messing with our `Protect_Campaign_Member_Statuses__c` value.
	 */
	public void beforeUpdate() {
		for (Campaign camp : newRecords) {
			Campaign oldCamp = oldRecordsMap.get(camp.Id);
			if (oldCamp == null) {
				continue;
			}
			if (camp.Protect_Campaign_Member_Statuses__c && (camp.Type != oldCamp.Type)) {
				camp.addError('Type', System.Label.CMS_Do_Not_Change_Type);
			}

			if (camp.Protect_Campaign_Member_Statuses__c && !oldCamp.Protect_Campaign_Member_Statuses__c) {
				camp.addError('Protect_Campaign_Member_Statuses__c', System.Label.CMS_Cannot_Re_enable);
			}
		}
	}
}