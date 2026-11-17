/**
 * @description Applies and enforces the protected Campaign Member Statuses for each Campaign Type.
 * <br>Singleton per transaction so configuration is read and normalised once.
 * <br><br>`without sharing` is deliberate: this is integrity automation called from the Campaign
 * trigger, the change event trigger (which runs as the Automated Process user) and the nightly
 * job. It must see and repair every protected Campaign whatever the running user's record access.
 * Every query and DML statement states SYSTEM_MODE so the intent is explicit and survives API
 * version upgrades. There are no user-facing entry points in this class.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public virtual without sharing class CampaignMemberService {
	/**
	 * New statuses start after the two statuses Salesforce creates on every Campaign, so a
	 * generated SortOrder never collides with them, even when they aren't visible (for example in tests).
	 */
	private static final Integer LAST_PLATFORM_SORT_ORDER = 2;

	@TestVisible
	private static CampaignMemberService instance;

	@TestVisible
	private CampaignMemberRepository repo;

	private Map<String, List<Campaign_Type_Member_Status__mdt>> statusesByType;

	/**
	 * @description Return the transaction's service instance, creating it on first use
	 *
	 * @return      `CampaignMemberService`
	 */
	public static CampaignMemberService getInstance() {
		if (instance == null) {
			instance = new CampaignMemberService();
			instance.repo = new CampaignMemberRepository();
		}
		return instance;
	}

	/**
	 * @description Replace the configuration source (used by tests) and clear the cached configuration
	 *
	 * @param repository Repository that supplies `Campaign_Type_Member_Status__mdt` records
	 */
	@TestVisible
	private void setRepository(CampaignMemberRepository repository) {
		this.repo = repository;
		this.statusesByType = null;
	}

	/**
	 * @description Active, normalised configuration grouped by Campaign Type
	 *
	 * @return      `Map<String, List<Campaign_Type_Member_Status__mdt>>` keyed by lower-case Campaign Type
	 * @see CMS_StatusRules.groupActiveByType
	 */
	public virtual Map<String, List<Campaign_Type_Member_Status__mdt>> getGroupedProtectedStatuses() {
		if (statusesByType == null) {
			statusesByType = CMS_StatusRules.groupActiveByType(repo.getAllStatusRecords());
		}
		return statusesByType;
	}

	/**
	 * @description Protected statuses for one Campaign Type (case-insensitive)
	 *
	 * @param campaignType Campaign Type picklist value
	 * @return             `List<Campaign_Type_Member_Status__mdt>` default first; empty when the type isn't protected
	 */
	public List<Campaign_Type_Member_Status__mdt> getProtectedStatusesForType(String campaignType) {
		List<Campaign_Type_Member_Status__mdt> statuses = String.isBlank(campaignType) ? null : getGroupedProtectedStatuses().get(CMS_StatusRules.toKey(campaignType));
		return statuses == null ? new List<Campaign_Type_Member_Status__mdt>() : statuses;
	}

	/**
	 * @description Whether a Campaign Type has active protected statuses
	 *
	 * @param campaignType Campaign Type picklist value
	 * @return             `Boolean`
	 */
	public Boolean isProtectedType(String campaignType) {
		return !getProtectedStatusesForType(campaignType).isEmpty();
	}

	/**
	 * @description Campaign Types that have active protected statuses
	 *
	 * @return      `Set<String>` lower-case Campaign Types (SOQL comparisons are case-insensitive)
	 */
	public Set<String> getProtectedTypes() {
		return new Set<String>(getGroupedProtectedStatuses().keySet());
	}

	/**
	 * @description       Query protected Campaigns with their current statuses
	 *
	 * @param campaignIds Campaigns to read; unprotected Campaigns are ignored
	 * @return            `List<Campaign>` with child `CampaignMemberStatuses` ordered by SortOrder
	 */
	public List<Campaign> getCampaignsWithMemberStatuses(Set<Id> campaignIds) {
		if (campaignIds == null || campaignIds.isEmpty()) {
			return new List<Campaign>();
		}
		return [
			SELECT
				Id,
				Name,
				Type,
				(
					SELECT Id, Label, CampaignId, HasResponded, IsDefault, SortOrder
					FROM CampaignMemberStatuses
					ORDER BY SortOrder ASC
				)
			FROM Campaign
			WHERE Id IN :campaignIds AND Protect_Campaign_Member_Statuses__c = TRUE
			WITH SYSTEM_MODE
		];
	}

	/**
	 * @description       Restore missing protected statuses and their Default and Responded settings.
	 *                    Never deletes statuses, so statuses users add for their own reasons survive.
	 *
	 * @param campaignIds Campaigns to check
	 * @return            `Map<Id, String>` error message by Campaign Id for any Campaign that couldn't be fixed
	 */
	public virtual Map<Id, String> enforceProtectedStatusesForCampaigns(Set<Id> campaignIds) {
		return applyProtectedStatuses(campaignIds, false);
	}

	/**
	 * @description       Give newly created protected Campaigns exactly their configured statuses:
	 *                    add the protected statuses, set the default, then remove the statuses
	 *                    Salesforce created automatically that aren't part of the configuration.
	 *
	 * @param campaignIds Newly inserted Campaigns
	 * @return            `Map<Id, String>` error message by Campaign Id for any Campaign that couldn't be set up
	 */
	public virtual Map<Id, String> applyProtectedStatusesToNewCampaigns(Set<Id> campaignIds) {
		return applyProtectedStatuses(campaignIds, true);
	}

	private Map<Id, String> applyProtectedStatuses(Set<Id> campaignIds, Boolean removeUnexpectedStatuses) {
		Map<Id, String> errorsByCampaignId = new Map<Id, String>();
		List<Campaign> campaigns = getCampaignsWithMemberStatuses(campaignIds);
		if (campaigns.isEmpty()) {
			return errorsByCampaignId;
		}

		StatusChangePlan plan = new StatusChangePlan();
		for (Campaign camp : campaigns) {
			planCampaign(camp, plan, removeUnexpectedStatuses);
		}

		// Order matters: new statuses need Ids before one can become the default, and an old
		// default can only be deleted once another status has taken over as default.
		insertStatuses(plan, errorsByCampaignId);
		plan.queueDefaultChanges();
		updateStatuses(plan, errorsByCampaignId);
		deleteStatuses(plan, errorsByCampaignId);
		return errorsByCampaignId;
	}

	private void planCampaign(Campaign camp, StatusChangePlan plan, Boolean removeUnexpectedStatuses) {
		List<Campaign_Type_Member_Status__mdt> expectedStatuses = getProtectedStatusesForType(camp.Type);
		if (expectedStatuses.isEmpty()) {
			// The Campaign is flagged as protected but its Type is no longer configured. Leave it alone.
			return;
		}

		Map<String, CampaignMemberStatus> existingByLabel = new Map<String, CampaignMemberStatus>();
		Integer highestSortOrder = LAST_PLATFORM_SORT_ORDER;
		for (CampaignMemberStatus existing : camp.CampaignMemberStatuses) {
			existingByLabel.put(CMS_StatusRules.toKey(existing.Label), existing);
			if (existing.SortOrder != null && existing.SortOrder > highestSortOrder) {
				highestSortOrder = existing.SortOrder;
			}
		}

		Set<String> expectedLabelKeys = new Set<String>();
		for (Campaign_Type_Member_Status__mdt expected : expectedStatuses) {
			String labelKey = CMS_StatusRules.toKey(expected.Campaign_Member_Status__c);
			expectedLabelKeys.add(labelKey);
			CampaignMemberStatus existing = existingByLabel.get(labelKey);

			if (existing == null) {
				highestSortOrder++;
				CampaignMemberStatus created = new CampaignMemberStatus(
					CampaignId = camp.Id,
					Label = expected.Campaign_Member_Status__c,
					HasResponded = expected.HasResponded__c,
					SortOrder = highestSortOrder
				);
				plan.addInsert(created);
				if (expected.IsDefault__c) {
					plan.defaultByCampaignId.put(camp.Id, created);
				}
				continue;
			}

			if (!existing.Label.equals(expected.Campaign_Member_Status__c)) {
				plan.getUpdate(existing.Id, camp.Id).Label = expected.Campaign_Member_Status__c;
			}
			if (existing.HasResponded != expected.HasResponded__c) {
				plan.getUpdate(existing.Id, camp.Id).HasResponded = expected.HasResponded__c;
			}
			if (expected.IsDefault__c && !existing.IsDefault) {
				plan.defaultByCampaignId.put(camp.Id, existing);
			}
		}

		if (removeUnexpectedStatuses) {
			for (CampaignMemberStatus existing : camp.CampaignMemberStatuses) {
				if (!expectedLabelKeys.contains(CMS_StatusRules.toKey(existing.Label))) {
					plan.addDelete(existing);
				}
			}
		}
	}

	private void insertStatuses(StatusChangePlan plan, Map<Id, String> errorsByCampaignId) {
		if (plan.inserts.isEmpty()) {
			return;
		}
		List<Database.SaveResult> results = Database.insert(plan.inserts, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess()) {
				recordError(errorsByCampaignId, plan.inserts[i].CampaignId, results[i].getErrors());
			}
		}
	}

	private void updateStatuses(StatusChangePlan plan, Map<Id, String> errorsByCampaignId) {
		if (plan.updatesById.isEmpty()) {
			return;
		}
		List<CampaignMemberStatus> updates = plan.updatesById.values();
		List<Database.SaveResult> results = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess()) {
				recordError(errorsByCampaignId, plan.campaignIdByStatusId.get(updates[i].Id), results[i].getErrors());
			}
		}
	}

	private void deleteStatuses(StatusChangePlan plan, Map<Id, String> errorsByCampaignId) {
		List<CampaignMemberStatus> deletes = new List<CampaignMemberStatus>();
		for (CampaignMemberStatus status : plan.deletes) {
			// Don't remove anything from a Campaign whose new statuses or default failed to save.
			if (!errorsByCampaignId.containsKey(status.CampaignId)) {
				deletes.add(status);
			}
		}
		if (deletes.isEmpty()) {
			return;
		}
		List<Database.DeleteResult> results = Database.delete(deletes, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess()) {
				recordError(errorsByCampaignId, deletes[i].CampaignId, results[i].getErrors());
			}
		}
	}

	private static void recordError(Map<Id, String> errorsByCampaignId, Id campaignId, List<Database.Error> errors) {
		List<String> messages = new List<String>();
		for (Database.Error error : errors) {
			messages.add(error.getMessage());
		}
		String message = String.join(messages, '; ');
		if (errorsByCampaignId.containsKey(campaignId)) {
			message = errorsByCampaignId.get(campaignId) + '; ' + message;
		}
		errorsByCampaignId.put(campaignId, message);
	}

	/**
	 * @description Collects the inserts, updates and deletes needed so they run as three bulk DML statements
	 */
	private class StatusChangePlan {
		public List<CampaignMemberStatus> inserts = new List<CampaignMemberStatus>();
		public Map<Id, CampaignMemberStatus> updatesById = new Map<Id, CampaignMemberStatus>();
		public Map<Id, Id> campaignIdByStatusId = new Map<Id, Id>();
		public Map<Id, CampaignMemberStatus> defaultByCampaignId = new Map<Id, CampaignMemberStatus>();
		public List<CampaignMemberStatus> deletes = new List<CampaignMemberStatus>();

		/**
		 * @description  Queue a new status
		 *
		 * @param status Status to insert
		 */
		public void addInsert(CampaignMemberStatus status) {
			inserts.add(status);
		}

		/**
		 * @description  Queue a status for deletion
		 *
		 * @param status Status to delete
		 */
		public void addDelete(CampaignMemberStatus status) {
			deletes.add(status);
		}

		/**
		 * @description      Get the pending update for a status. Updates use a fresh record holding
		 *                   only the changed fields: re-saving a queried record would also re-send its
		 *                   old IsDefault value and could undo the new default.
		 *
		 * @param statusId   Status to update
		 * @param campaignId Its Campaign, for error reporting
		 * @return           `CampaignMemberStatus` pending update record
		 */
		public CampaignMemberStatus getUpdate(Id statusId, Id campaignId) {
			CampaignMemberStatus pending = updatesById.get(statusId);
			if (pending == null) {
				pending = new CampaignMemberStatus(Id = statusId);
				updatesById.put(statusId, pending);
				campaignIdByStatusId.put(statusId, campaignId);
			}
			return pending;
		}

		/**
		 * @description Queue the default changes once new statuses have Ids. Only ever sets IsDefault
		 *              to true: Salesforce clears the previous default itself, so the Campaign always
		 *              has exactly one default and never passes through a state with none.
		 */
		public void queueDefaultChanges() {
			for (Id campaignId : defaultByCampaignId.keySet()) {
				CampaignMemberStatus newDefault = defaultByCampaignId.get(campaignId);
				if (newDefault.Id != null) {
					getUpdate(newDefault.Id, campaignId).IsDefault = true;
				}
			}
		}
	}
}