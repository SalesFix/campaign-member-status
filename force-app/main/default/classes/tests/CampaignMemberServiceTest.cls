/**
 * @description Tests for `CampaignMemberService` enforcement
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CampaignMemberServiceTest {
	private static Campaign createProtectedWebinar() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		Assert.isTrue(
			[SELECT Protect_Campaign_Member_Statuses__c FROM Campaign WHERE Id = :camp.Id].Protect_Campaign_Member_Statuses__c,
			'Setup: the webinar Campaign should be protected'
		);
		return camp;
	}

	@isTest
	private static void shouldRestoreMissingStatusWhenProtectedStatusDeleted() {
		Campaign camp = createProtectedWebinar();
		delete [SELECT Id FROM CampaignMemberStatus WHERE CampaignId = :camp.Id AND Label = :CMS_TestDataFactory.WATCHED_ON_DEMAND];

		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.isTrue(errors.isEmpty(), 'No errors expected: ' + errors);
		Assert.isTrue(statuses.containsKey(CMS_TestDataFactory.WATCHED_ON_DEMAND), 'The deleted protected status is restored');
		Assert.isTrue(statuses.get(CMS_TestDataFactory.WATCHED_ON_DEMAND).HasResponded, 'The restored status counts as Responded');
	}

	@isTest
	private static void shouldResetRespondedWhenUserChangesIt() {
		Campaign camp = createProtectedWebinar();
		CampaignMemberStatus registered = CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.REGISTERED);
		registered.HasResponded = true;
		update registered;

		Test.startTest();
		CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		Assert.isFalse(CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.REGISTERED).HasResponded, 'Registered is configured as not Responded');
	}

	@isTest
	private static void shouldRestoreConfiguredDefaultWhenUserChangesDefault() {
		Campaign camp = createProtectedWebinar();
		CampaignMemberStatus attended = CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.ATTENDED);
		attended.IsDefault = true;
		update attended;

		Test.startTest();
		CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		Map<String, CampaignMemberStatus> statuses = CMS_TestDataFactory.statusesByLabel(camp.Id);
		Assert.isTrue(statuses.get(CMS_TestDataFactory.REGISTERED).IsDefault, 'Registered is the configured default');
		Assert.isFalse(statuses.get(CMS_TestDataFactory.ATTENDED).IsDefault, 'Only one status can be the default');
	}

	@isTest
	private static void shouldRestoreExactLabelWhenOnlyCaseChanged() {
		Campaign camp = createProtectedWebinar();
		CampaignMemberStatus attended = CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.ATTENDED);
		attended.Label = CMS_TestDataFactory.ATTENDED.toLowerCase();
		update attended;

		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		List<CampaignMemberStatus> attendedStatuses = [SELECT Label FROM CampaignMemberStatus WHERE CampaignId = :camp.Id AND Label = :CMS_TestDataFactory.ATTENDED];
		Assert.isTrue(errors.isEmpty(), 'Matching is case-insensitive, so no duplicate insert is attempted: ' + errors);
		Assert.areEqual(1, attendedStatuses.size(), 'Exactly one Attended status');
		Assert.areEqual(CMS_TestDataFactory.ATTENDED, attendedStatuses[0].Label, 'The configured capitalisation is restored');
	}

	@isTest
	private static void shouldKeepExtraStatusesWhenEnforcingExistingCampaign() {
		Campaign camp = createProtectedWebinar();
		insert new CampaignMemberStatus(CampaignId = camp.Id, Label = 'Extra', SortOrder = 50);

		Test.startTest();
		CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		Assert.isTrue(CMS_TestDataFactory.statusesByLabel(camp.Id).containsKey('Extra'), 'Statuses users add for their own reasons are kept');
	}

	@isTest
	private static void shouldSkipCampaignWhenTypeNoLongerConfigured() {
		Campaign camp = createProtectedWebinar();
		Integer statusCountBefore = CMS_TestDataFactory.statusesByLabel(camp.Id).size();
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());

		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ camp.Id });
		Test.stopTest();

		Assert.isTrue(errors.isEmpty(), 'A protected Campaign whose Type was removed from the configuration is skipped, not an error');
		Assert.areEqual(statusCountBefore, CMS_TestDataFactory.statusesByLabel(camp.Id).size(), 'Its statuses are left alone');
	}

	@isTest
	private static void shouldReturnNoErrorsWhenIdsNull() {
		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(null);
		Test.stopTest();

		Assert.isTrue(errors.isEmpty(), 'Nothing to do for null input');
	}

	@isTest
	private static void shouldReturnNoErrorsWhenIdsEmpty() {
		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>());
		Test.stopTest();

		Assert.isTrue(errors.isEmpty(), 'Nothing to do for empty input');
	}

	@isTest
	private static void shouldFixOtherCampaignsWhenOneCampaignFails() {
		List<Campaign_Type_Member_Status__mdt> config = CMS_TestDataFactory.webinarConfig();
		config.addAll(CMS_TestDataFactory.advertisementConfig());
		CMS_TestDataFactory.useConfiguration(config);
		Campaign webinar = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		Campaign advert = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.ADVERTISEMENT, true)[0];
		delete [SELECT Id FROM CampaignMemberStatus WHERE CampaignId = :webinar.Id AND Label = :CMS_TestDataFactory.DID_NOT_ATTEND];

		// A status name far longer than any Campaign Member Status label allows, so only the advert fails to save.
		config.add(CMS_TestDataFactory.status(CMS_TestDataFactory.ADVERTISEMENT, 'X'.repeat(1000), false, false));
		CMS_TestDataFactory.useConfiguration(config);

		Test.startTest();
		Map<Id, String> errors = CampaignMemberService.getInstance().enforceProtectedStatusesForCampaigns(new Set<Id>{ webinar.Id, advert.Id });
		Test.stopTest();

		Assert.isTrue(errors.containsKey(advert.Id), 'The failing Campaign is reported');
		Assert.isFalse(errors.containsKey(webinar.Id), 'The other Campaign is not affected');
		Assert.isTrue(CMS_TestDataFactory.statusesByLabel(webinar.Id).containsKey(CMS_TestDataFactory.DID_NOT_ATTEND), 'The other Campaign is still repaired');
	}

	@isTest
	private static void shouldReportProtectedTypesInLowerCase() {
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());

		Test.startTest();
		Set<String> protectedTypes = CampaignMemberService.getInstance().getProtectedTypes();
		Boolean upperCaseIsProtected = CampaignMemberService.getInstance().isProtectedType('WEBINAR');
		Test.stopTest();

		Assert.areEqual(new Set<String>{ 'webinar' }, protectedTypes, 'Types are keyed in lower case');
		Assert.isTrue(upperCaseIsProtected, 'Type matching is case-insensitive');
	}
}