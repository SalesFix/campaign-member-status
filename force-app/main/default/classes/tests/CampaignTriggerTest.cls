/**
 * @description Tests for the Campaign trigger handler (`CMS_CampaignTriggerHandler`).
 * Requires the sample Campaign trigger in `unpackaged/triggers-sample` (or your own) to be deployed.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CampaignTriggerTest {
	private static final Integer BULK_SIZE = 251;

	@isTest
	private static void shouldRejectCampaignWhenUserTicksProtectBox() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, false)[0];
		camp.Protect_Campaign_Member_Statuses__c = true;

		Test.startTest();
		Database.SaveResult result = Database.insert(camp, false);
		Test.stopTest();

		Assert.isFalse(result.isSuccess(), 'Users may not tick the protect box themselves');
		Assert.areEqual(System.Label.CMS_Do_not_check_box_on_Campaign_Create, result.getErrors()[0].getMessage(), 'The user sees why');
	}

	@isTest
	private static void shouldProtectCampaignWhenTypeConfigured() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		Test.stopTest();

		Assert.isTrue([SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :camp.Id].Protect_Campaign_Member_Statuses__c, 'Webinar is protected');
	}

	@isTest
	private static void shouldProtectCampaignWhenTypeCaseDiffers() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, 'webinar', true)[0];
		Test.stopTest();

		Assert.isTrue([SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :camp.Id].Protect_Campaign_Member_Statuses__c, 'Type matching is case-insensitive');
	}

	@isTest
	private static void shouldNotProtectCampaignWhenTypeNotConfigured() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.UNPROTECTED_TYPE, true)[0];
		Test.stopTest();

		Assert.isFalse([SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :camp.Id].Protect_Campaign_Member_Statuses__c, 'Unconfigured types are left alone');
	}

	@isTest
	private static void shouldCreateExactlyConfiguredStatusesWhenProtectedCampaignInserted() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.areEqual(
			new Set<String>{ CMS_TestDataFactory.REGISTERED, CMS_TestDataFactory.ATTENDED, CMS_TestDataFactory.WATCHED_ON_DEMAND, CMS_TestDataFactory.DID_NOT_ATTEND },
			statuses.keySet(),
			'The Campaign has exactly the configured statuses'
		);
		Assert.isTrue(statuses.get(CMS_TestDataFactory.REGISTERED).IsDefault, 'Registered is the default');
		Assert.isTrue(statuses.get(CMS_TestDataFactory.ATTENDED).HasResponded, 'Attended counts as Responded');
		Assert.isFalse(statuses.get(CMS_TestDataFactory.DID_NOT_ATTEND).HasResponded, 'Did Not Attend does not count as Responded');
	}

	@isTest
	private static void shouldHonourRespondedSettingWhenTypeHasSingleStatus() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.advertisementConfig());

		Test.startTest();
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, true)[0];
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.areEqual(new Set<String>{ CMS_TestDataFactory.SEEN }, statuses.keySet(), 'Only the single configured status remains');
		Assert.isTrue(statuses.get(CMS_TestDataFactory.SEEN).IsDefault, 'It is the default');
		Assert.isFalse(statuses.get(CMS_TestDataFactory.SEEN).HasResponded, 'The configured Responded setting (false) is honoured');
	}

	@isTest
	private static void shouldApplyStatusesToEveryCampaignWhenBulkInserted() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		List<Campaign> campaigns = CMS_TestDataFactory.createCampaigns(BULK_SIZE, CMS_TestDataFactory.WEBINAR, true);
		Test.stopTest();

		Set<Id> campaignIds = new Map<Id, Campaign>(campaigns).keySet();
		Integer expectedStatuses = BULK_SIZE * CMS_TestDataFactory.webinarConfig().size();
		Assert.areEqual(expectedStatuses, [SELECT COUNT() FROM CampaignMemberStatus WHERE CampaignId IN :campaignIds], 'Every Campaign gets all four statuses');
		Assert.areEqual(
			BULK_SIZE,
			[SELECT COUNT() FROM CampaignMemberStatus WHERE CampaignId IN :campaignIds AND IsDefault = TRUE AND Label = :CMS_TestDataFactory.REGISTERED],
			'Every Campaign has Registered as its default'
		);
	}

	@isTest
	private static void shouldProtectCloneWhenSourceWasNotProtected() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		Campaign original = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign source = [SELECT Name, Type, IsActive, Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :original.Id];
		// Clone the record, not the query result list (a list clone keeps the original Id).
		Campaign clonedCampaign = source.clone();
		clonedCampaign.Name = 'CMS Test clone';

		Test.startTest();
		insert clonedCampaign;
		Test.stopTest();

		Assert.isTrue(
			[SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :clonedCampaign.Id].Protect_Campaign_Member_Statuses__c,
			'A clone is protected from its own Type, even if its source was created before the Type was configured'
		);
		Assert.areEqual(4, CMS_TestDataFactory.statusesByLabel(clonedCampaign.Id).size(), 'The clone gets the configured statuses');
	}

	@isTest
	private static void shouldNotProtectCloneWhenTypeChangedToUnconfiguredType() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign original = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		Campaign source = [SELECT Name, Type, IsActive, Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :original.Id];
		// Clone the record, not the query result list (a list clone keeps the original Id).
		Campaign clonedCampaign = source.clone();
		clonedCampaign.Name = 'CMS Test clone';
		clonedCampaign.Type = CMS_TestDataFactory.UNPROTECTED_TYPE;

		Test.startTest();
		Database.SaveResult result = Database.insert(clonedCampaign, false);
		Test.stopTest();

		Assert.isTrue(result.isSuccess(), 'Cloning with a different Type must not fail: ' + result.getErrors());
		Assert.isFalse(
			[SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :clonedCampaign.Id].Protect_Campaign_Member_Statuses__c,
			'The clone is not protected because its new Type is not configured'
		);
	}

	@isTest
	private static void shouldRejectTypeChangeWhenCampaignProtected() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.advertisementConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, true)[0];
		camp.Type = CMS_TestDataFactory.WEBINAR;

		Test.startTest();
		Database.SaveResult result = Database.update(camp, false);
		Test.stopTest();

		Assert.isFalse(result.isSuccess(), 'The Type of a protected Campaign cannot change');
		Assert.areEqual(System.Label.CMS_Do_Not_Change_Type, result.getErrors()[0].getMessage(), 'The user sees why');
	}

	@isTest
	private static void shouldRejectReEnablingWhenProtectionWasOff() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.UNPROTECTED_TYPE, true)[0];
		camp.Protect_Campaign_Member_Statuses__c = true;

		Test.startTest();
		Database.SaveResult result = Database.update(camp, false);
		Test.stopTest();

		Assert.isFalse(result.isSuccess(), 'Protection cannot be switched back on');
		Assert.areEqual(System.Label.CMS_Cannot_Re_enable, result.getErrors()[0].getMessage(), 'The user sees why');
	}

	@isTest
	private static void shouldRejectCampaignWhenStatusesCannotBeApplied() {
		List<Campaign_Type_Member_Status__mdt> config = CMS_TestDataFactory.advertisementConfig();
		config.add(CMS_TestDataFactory.status(CMS_TestDataFactory.ADVERTISEMENT, 'X'.repeat(1000), false, false));
		CMS_TestDataFactory.useConfiguration(config);
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, false)[0];

		Test.startTest();
		Database.SaveResult result = Database.insert(camp, false);
		Test.stopTest();

		Assert.isFalse(result.isSuccess(), 'A Campaign is never saved with the wrong statuses');
		Assert.isTrue(result.getErrors()[0].getMessage().startsWith(System.Label.CMS_Could_Not_Apply_Statuses.substringBefore('{0}')), 'The user sees why');
	}

	/**
	 * Salesforce only exposes the "Sent" and "Responded" statuses it creates on every new Campaign
	 * to tests that can see org data. This single test uses seeAllData to prove those automatic
	 * statuses are replaced by the configured ones on a real Campaign insert.
	 */
	@SuppressWarnings('PMD.ApexUnitTestShouldNotUseSeeAllDataTrue')
	@isTest(seeAllData=true)
	private static void shouldReplacePlatformDefaultStatusesWhenProtectedCampaignInserted() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = new Campaign(Name = 'CMS platform defaults ' + Crypto.getRandomInteger(), Type = CMS_TestDataFactory.WEBINAR, IsActive = true);

		Test.startTest();
		insert camp;
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.areEqual(4, statuses.size(), 'Only the four configured statuses remain: ' + statuses.keySet());
		Assert.isFalse(statuses.containsKey('Sent'), 'The automatic Sent status is removed');
		Assert.isTrue(statuses.get(CMS_TestDataFactory.REGISTERED).IsDefault, 'Registered replaced Sent as the default');
	}
}