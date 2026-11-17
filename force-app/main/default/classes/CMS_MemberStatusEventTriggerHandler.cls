/**
 * @description Change Data Capture handler for `CampaignMemberStatusChangeEvent`. When a status on
 * a protected Campaign is edited, the Campaign's protected statuses are checked and repaired.
 * <br>Deleted statuses can't be traced back to their Campaign from a change event, so deletions
 * are repaired by the nightly `CampaignMemberStatusJob`.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      David Schach
 * @since       2023
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public inherited sharing class CMS_MemberStatusEventTriggerHandler {
	private static final Set<String> CHANGE_TYPES_TO_PROCESS = new Set<String>{ 'UPDATE', 'GAP_UPDATE' };
	private static final String AUTOMATED_PROCESS_USER_TYPE = 'AutomatedProcess';

	private List<CampaignMemberStatusChangeEvent> newRecords;

	/**
	 * @description Constructor used by the change event trigger
	 */
	public CMS_MemberStatusEventTriggerHandler() {
		this((List<CampaignMemberStatusChangeEvent>) Trigger.new);
	}

	/**
	 * @description        Constructor for tests and other trigger frameworks
	 *
	 * @param newRecords   `Trigger.new`
	 */
	public CMS_MemberStatusEventTriggerHandler(List<CampaignMemberStatusChangeEvent> newRecords) {
		this.newRecords = newRecords == null ? new List<CampaignMemberStatusChangeEvent>() : newRecords;
	}

	/**
	 * @description Execute after inserting (creating) change event records
	 */
	public void afterInsert() {
		Id runningUserId = UserInfo.getUserId();
		Boolean runningAsAutomatedProcess = UserInfo.getUserType() == AUTOMATED_PROCESS_USER_TYPE;
		Set<Id> statusIds = new Set<Id>();

		for (CampaignMemberStatusChangeEvent event : newRecords) {
			EventBus.ChangeEventHeader header = event.ChangeEventHeader;
			if (!shouldProcess(header.changeType, header.commitUser, runningUserId, runningAsAutomatedProcess)) {
				continue;
			}
			for (String recordId : header.getRecordIds()) {
				statusIds.add(Id.valueOf(recordId));
			}
		}
		if (statusIds.isEmpty()) {
			return;
		}

		Set<Id> campaignIds = new Set<Id>();
		for (CampaignMemberStatus status : [SELECT CampaignId FROM CampaignMemberStatus WHERE Id IN :statusIds WITH SYSTEM_MODE]) {
			campaignIds.add(status.CampaignId);
		}

		Map<Id, String> errorsByCampaignId = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(campaignIds);
		if (!errorsByCampaignId.isEmpty()) {
			// Not fatal: the nightly job retries every protected Campaign.
			System.debug(LoggingLevel.ERROR, 'CMS: could not enforce statuses for Campaigns ' + errorsByCampaignId);
		}
	}

	/**
	 * @description Decide whether a change event should trigger enforcement.
	 * <br>Our own repairs are committed by the Automated Process user that runs this trigger.
	 * Ignoring those events means a repair can never set off another repair, so a conflicting
	 * configuration can't cause an endless update loop.
	 *
	 * @param changeType                 `ChangeEventHeader` change type
	 * @param commitUser                 Id of the user who committed the change
	 * @param runningUserId              Id of the user running this trigger
	 * @param runningAsAutomatedProcess  True when the trigger runs as the Automated Process user
	 * @return                           `Boolean`
	 */
	@TestVisible
	private static Boolean shouldProcess(String changeType, String commitUser, Id runningUserId, Boolean runningAsAutomatedProcess) {
		if (!CHANGE_TYPES_TO_PROCESS.contains(changeType)) {
			return false;
		}
		Boolean isOwnRepair = runningAsAutomatedProcess && String.isNotBlank(commitUser) && Id.valueOf(commitUser) == runningUserId;
		return !isOwnRepair;
	}
}