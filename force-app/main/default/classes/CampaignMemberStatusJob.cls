/**
 * @description Nightly repair of protected Campaign Member Statuses.
 * <br>Schedule this class (Setup > Apex Classes > Schedule Apex, or `CampaignMemberStatusJob.scheduleDaily()`).
 * Each run starts a batch over every active protected Campaign whose Type is still configured,
 * so the work is chunked and stays inside governor limits however many Campaigns there are.
 * It restores deleted protected statuses and corrects Default and Responded settings.
 * <br><br>`without sharing` is deliberate: the job must reach every protected Campaign, not only
 * those the scheduling user can see. Queries state SYSTEM_MODE explicitly.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public without sharing class CampaignMemberStatusJob implements Schedulable, Database.Batchable<SObject>, Database.Stateful {
	/**
	 * @description Name used by `scheduleDaily()`
	 */
	public static final String DEFAULT_JOB_NAME = 'Campaign Member Status nightly repair';

	/**
	 * @description Every day at 2:00 am in the scheduling user's time zone
	 */
	public static final String DAILY_CRON_EXPRESSION = '0 0 2 * * ?';

	/**
	 * @description Campaigns per batch chunk
	 */
	public static final Integer BATCH_SIZE = 200;

	@TestVisible
	private Integer campaignsWithErrors = 0;

	/**
	 * @description Scheduled entry point: start the batch
	 *
	 * @param context `SchedulableContext`
	 */
	public void execute(SchedulableContext context) {
		Database.executeBatch(new CampaignMemberStatusJob(), BATCH_SIZE);
	}

	/**
	 * @description Select every active protected Campaign whose Type is configured
	 *
	 * @param context `Database.BatchableContext`
	 * @return        `Database.QueryLocator`
	 */
	public Database.QueryLocator start(Database.BatchableContext context) {
		Set<String> protectedTypes = CampaignMemberService.getInstance().getProtectedTypes();
		return Database.getQueryLocator(
			[
				SELECT Id
				FROM Campaign
				WHERE Protect_Campaign_Member_Statuses__c = TRUE AND IsActive = TRUE AND Type IN :protectedTypes
				WITH SYSTEM_MODE
				ORDER BY Id
			]
		);
	}

	/**
	 * @description Repair one chunk of Campaigns
	 *
	 * @param context `Database.BatchableContext`
	 * @param scope   Campaigns in this chunk
	 */
	public void execute(Database.BatchableContext context, List<Campaign> scope) {
		Map<Id, String> errorsByCampaignId = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Map<Id, Campaign>(scope).keySet());
		if (!errorsByCampaignId.isEmpty()) {
			campaignsWithErrors += errorsByCampaignId.size();
			System.debug(LoggingLevel.ERROR, 'CMS: could not repair statuses for Campaigns ' + errorsByCampaignId);
		}
	}

	/**
	 * @description Report how many Campaigns couldn't be repaired
	 *
	 * @param context `Database.BatchableContext`
	 */
	public void finish(Database.BatchableContext context) {
		if (campaignsWithErrors > 0) {
			System.debug(LoggingLevel.ERROR, 'CMS: nightly repair finished; ' + campaignsWithErrors + ' Campaign(s) could not be repaired.');
		}
	}

	/**
	 * @description Schedule the nightly repair at 2:00 am
	 *
	 * @return      `Id` the CronTrigger Id
	 * @example
	 * CampaignMemberStatusJob.scheduleDaily();
	 */
	public static Id scheduleDaily() {
		return System.schedule(DEFAULT_JOB_NAME, DAILY_CRON_EXPRESSION, new CampaignMemberStatusJob());
	}
}