/**
 * @description Tests for the nightly repair job (`CampaignMemberStatusJob`)
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CampaignMemberStatusJobTest {
	private static final Integer BULK_SIZE = 251;

	private static void deleteStatus(Set<Id> campaignIds, String label) {
		delete [SELECT Id FROM CampaignMemberStatus WHERE CampaignId IN :campaignIds AND Label = :label];
	}

	@isTest
	private static void shouldRestoreDeletedStatusesWhenBatchRuns() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Set<Id> campaignIds = new Map<Id, Campaign>(CMS_TestDataFactory.createCampaigns(BULK_SIZE, CMS_TestDataFactory.WEBINAR, true)).keySet();
		deleteStatus(campaignIds, CMS_TestDataFactory.ATTENDED);

		Test.startTest();
		// In tests only one execute() runs, so the scope must cover every record.
		Database.executeBatch(new CampaignMemberStatusJob(), BULK_SIZE);
		Test.stopTest();

		Assert.areEqual(
			BULK_SIZE,
			[SELECT COUNT() FROM CampaignMemberStatus WHERE CampaignId IN :campaignIds AND Label = :CMS_TestDataFactory.ATTENDED],
			'Attended is restored on every Campaign'
		);
	}

	@isTest
	private static void shouldRestoreCampaignWithNoMatchingStatusesWhenBatchRuns() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.advertisementConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, true)[0];
		insert new CampaignMemberStatus(CampaignId = camp.Id, Label = 'Replacement', SortOrder = 10, IsDefault = false);
		CampaignMemberStatus replacement = [SELECT Id FROM CampaignMemberStatus WHERE CampaignId = :camp.Id AND Label = 'Replacement'];
		replacement.IsDefault = true;
		update replacement;
		deleteStatus(new Set<Id>{ camp.Id }, CMS_TestDataFactory.SEEN);

		Test.startTest();
		Database.executeBatch(new CampaignMemberStatusJob(), CampaignMemberStatusJob.BATCH_SIZE);
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.isTrue(statuses.containsKey(CMS_TestDataFactory.SEEN), 'A Campaign with none of its protected statuses left is still found and repaired');
		Assert.isTrue(statuses.get(CMS_TestDataFactory.SEEN).IsDefault, 'Seen is the configured default again');
	}

	@isTest
	private static void shouldSkipInactiveCampaignsWhenBatchRuns() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		camp.IsActive = false;
		update camp;
		deleteStatus(new Set<Id>{ camp.Id }, CMS_TestDataFactory.ATTENDED);

		Test.startTest();
		Database.executeBatch(new CampaignMemberStatusJob(), CampaignMemberStatusJob.BATCH_SIZE);
		Test.stopTest();

		Assert.isFalse(CMS_TestDataFactory.statusesByLabel(camp.Id).containsKey(CMS_TestDataFactory.ATTENDED), 'Inactive Campaigns are not repaired');
	}

	@isTest
	private static void shouldStartBatchWhenScheduledJobRuns() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		new CampaignMemberStatusJob().execute((SchedulableContext) null);
		Test.stopTest();

		Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'CampaignMemberStatusJob'], 'The scheduled job starts the repair batch');
	}

	@isTest
	private static void shouldScheduleNightlyWhenScheduleDailyCalled() {
		Test.startTest();
		Id cronId = CampaignMemberStatusJob.scheduleDaily();
		Test.stopTest();

		CronTrigger scheduled = [SELECT CronExpression, CronJobDetail.Name FROM CronTrigger WHERE Id = :cronId];
		Assert.areEqual(CampaignMemberStatusJob.DAILY_CRON_EXPRESSION, scheduled.CronExpression, 'Scheduled for 2:00 am daily');
		Assert.areEqual(CampaignMemberStatusJob.DEFAULT_JOB_NAME, scheduled.CronJobDetail.Name, 'Uses the default job name');
	}

	@isTest
	private static void shouldCountFailuresWhenCampaignCannotBeRepaired() {
		List<Campaign_Type_Member_Status__mdt> config = CMS_TestDataFactory.advertisementConfig();
		CMS_TestDataFactory.useConfiguration(config);
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, true)[0];
		config.add(CMS_TestDataFactory.status(CMS_TestDataFactory.ADVERTISEMENT, 'X'.repeat(1000), false, false));
		CMS_TestDataFactory.useConfiguration(config);
		CampaignMemberStatusJob job = new CampaignMemberStatusJob();

		Test.startTest();
		job.execute((Database.BatchableContext) null, new List<Campaign>{ camp });
		job.finish(null);
		Test.stopTest();

		Assert.areEqual(1, job.campaignsWithErrors, 'The failing Campaign is counted and the job carries on');
	}
}