/**
 * @description Tests for `CMS_StatusRules`: grouping, case-insensitive matching and the single-default rule
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CMS_StatusRulesTest {
	@isTest
	private static void shouldReturnEmptyMapWhenRecordsNull() {
		Test.startTest();
		Map<String, List<Campaign_Type_Member_Status__mdt>> result = CMS_StatusRules.groupActiveByType(null);
		Test.stopTest();

		Assert.isTrue(result.isEmpty(), 'Null input should give an empty configuration');
	}

	@isTest
	private static void shouldReturnEmptyMapWhenRecordsEmpty() {
		Test.startTest();
		Map<String, List<Campaign_Type_Member_Status__mdt>> result = CMS_StatusRules.groupActiveByType(new List<Campaign_Type_Member_Status__mdt>());
		Test.stopTest();

		Assert.isTrue(result.isEmpty(), 'Empty input should give an empty configuration');
	}

	@isTest
	private static void shouldGroupByLowerCaseTypeWhenTypesDifferInCase() {
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{
			CMS_TestDataFactory.status('Webinar', 'Registered', true, false),
			CMS_TestDataFactory.status('WEBINAR ', 'Attended', false, true)
		};

		Test.startTest();
		Map<String, List<Campaign_Type_Member_Status__mdt>> result = CMS_StatusRules.groupActiveByType(config);
		Test.stopTest();

		Assert.areEqual(1, result.size(), 'Types that differ only in case or spacing are the same type');
		Assert.areEqual(2, result.get('webinar').size(), 'Both statuses belong to the webinar type');
	}

	@isTest
	private static void shouldIgnoreInactiveAndIncompleteRecords() {
		Campaign_Type_Member_Status__mdt inactive = CMS_TestDataFactory.status('Webinar', 'Old Status', false, false);
		inactive.Inactive__c = true;
		Campaign_Type_Member_Status__mdt noStatus = CMS_TestDataFactory.status('Webinar', ' ', false, false);
		Campaign_Type_Member_Status__mdt noType = CMS_TestDataFactory.status(null, 'Orphan', false, false);
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{
			CMS_TestDataFactory.status('Webinar', 'Registered', true, false),
			inactive,
			noStatus,
			noType
		};

		Test.startTest();
		Map<String, List<Campaign_Type_Member_Status__mdt>> result = CMS_StatusRules.groupActiveByType(config);
		Test.stopTest();

		Assert.areEqual(1, result.size(), 'Only the webinar type should be configured');
		Assert.areEqual(1, result.get('webinar').size(), 'Inactive and incomplete records are ignored');
		Assert.areEqual('Registered', result.get('webinar')[0].Campaign_Member_Status__c, 'The active status remains');
	}

	@isTest
	private static void shouldKeepOnlyFirstDefaultWhenSeveralMarkedDefault() {
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{
			CMS_TestDataFactory.status('Webinar', 'Zebra', true, false),
			CMS_TestDataFactory.status('Webinar', 'Apple', true, false)
		};

		Test.startTest();
		List<Campaign_Type_Member_Status__mdt> result = CMS_StatusRules.groupActiveByType(config).get('webinar');
		Test.stopTest();

		Assert.areEqual('Apple', result[0].Campaign_Member_Status__c, 'Defaults sort alphabetically, so Apple comes first');
		Assert.isTrue(result[0].IsDefault__c, 'The first default is kept');
		Assert.isFalse(result[1].IsDefault__c, 'Any other default is cleared so two defaults can never fight');
	}

	@isTest
	private static void shouldMakeFirstStatusDefaultWhenNoneMarkedDefault() {
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{
			CMS_TestDataFactory.status('Webinar', 'Registered', false, false),
			CMS_TestDataFactory.status('Webinar', 'Attended', false, true)
		};

		Test.startTest();
		List<Campaign_Type_Member_Status__mdt> result = CMS_StatusRules.groupActiveByType(config).get('webinar');
		Test.stopTest();

		Assert.areEqual('Attended', result[0].Campaign_Member_Status__c, 'Responded statuses sort first when there is no default');
		Assert.isTrue(result[0].IsDefault__c, 'The first status becomes the default');
		Assert.isFalse(result[1].IsDefault__c, 'Only one default');
	}

	@isTest
	private static void shouldIgnoreDuplicateStatusNamesWhenCaseDiffers() {
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{
			CMS_TestDataFactory.status('Webinar', 'Attended', false, true),
			CMS_TestDataFactory.status('Webinar', 'attended', false, true),
			CMS_TestDataFactory.status('Webinar', 'Registered', true, false)
		};

		Test.startTest();
		List<Campaign_Type_Member_Status__mdt> result = CMS_StatusRules.groupActiveByType(config).get('webinar');
		Test.stopTest();

		Assert.areEqual(2, result.size(), 'Duplicate status names are collapsed');
	}

	@isTest
	private static void shouldNotChangeSourceRecordsWhenNormalising() {
		Campaign_Type_Member_Status__mdt secondDefault = CMS_TestDataFactory.status('Webinar', 'Zebra', true, false);
		List<Campaign_Type_Member_Status__mdt> config = new List<Campaign_Type_Member_Status__mdt>{ CMS_TestDataFactory.status('Webinar', 'Apple', true, false), secondDefault };

		Test.startTest();
		CMS_StatusRules.groupActiveByType(config);
		Test.stopTest();

		Assert.isTrue(secondDefault.IsDefault__c, 'Normalising works on copies and leaves the source records untouched');
	}

	@isTest
	private static void shouldReturnNullKeyWhenValueNull() {
		Test.startTest();
		String key = CMS_StatusRules.toKey(null);
		Test.stopTest();

		Assert.isNull(key, 'A null value has a null key');
	}
}