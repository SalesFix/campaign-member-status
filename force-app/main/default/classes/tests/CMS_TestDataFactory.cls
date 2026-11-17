/**
 * @description Test data and configuration builders for the Campaign Member Status tests
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
public without sharing class CMS_TestDataFactory {
	public static final String WEBINAR = 'Webinar';
	public static final String ADVERTISEMENT = 'Advertisement';
	public static final String REGISTERED = 'Registered';
	public static final String ATTENDED = 'Attended';
	public static final String WATCHED_ON_DEMAND = 'Watched On Demand';
	public static final String DID_NOT_ATTEND = 'Did Not Attend';
	public static final String SEEN = 'Seen';
	public static final String UNPROTECTED_TYPE = 'Not Protected Type';

	/**
	 * @description Webinar: four statuses, Registered is the default, two count as Responded
	 *
	 * @return      `List<Campaign_Type_Member_Status__mdt>`
	 */
	public static List<Campaign_Type_Member_Status__mdt> webinarConfig() {
		return new List<Campaign_Type_Member_Status__mdt>{
			status(WEBINAR, REGISTERED, true, false),
			status(WEBINAR, ATTENDED, false, true),
			status(WEBINAR, WATCHED_ON_DEMAND, false, true),
			status(WEBINAR, DID_NOT_ATTEND, false, false)
		};
	}

	/**
	 * @description Advertisement: a single status that does NOT count as Responded
	 *
	 * @return      `List<Campaign_Type_Member_Status__mdt>`
	 */
	public static List<Campaign_Type_Member_Status__mdt> advertisementConfig() {
		return new List<Campaign_Type_Member_Status__mdt>{ status(ADVERTISEMENT, SEEN, true, false) };
	}

	/**
	 * @description         Build one in-memory configuration record
	 *
	 * @param campaignType  Campaign Type
	 * @param statusName    Campaign Member Status name
	 * @param isDefault     Default status
	 * @param hasResponded  Counts as Responded
	 * @return              `Campaign_Type_Member_Status__mdt`
	 */
	public static Campaign_Type_Member_Status__mdt status(String campaignType, String statusName, Boolean isDefault, Boolean hasResponded) {
		Campaign_Type_Member_Status__mdt config = new Campaign_Type_Member_Status__mdt();
		config.DeveloperName = (campaignType + '_' + statusName).replaceAll('[^A-Za-z0-9]+', '_');
		config.Label = (campaignType + '-' + statusName).left(40);
		config.Campaign_Type__c = campaignType;
		config.Campaign_Member_Status__c = statusName;
		config.IsDefault__c = isDefault;
		config.HasResponded__c = hasResponded;
		config.Inactive__c = false;
		return config;
	}

	/**
	 * @description         Use this configuration for the rest of the test (service and controller)
	 *
	 * @param configRecords Configuration records
	 */
	public static void useConfiguration(List<Campaign_Type_Member_Status__mdt> configRecords) {
		CampaignMemberRepositoryMocks.ConfiguredMock mock = new CampaignMemberRepositoryMocks.ConfiguredMock(configRecords);
		CampaignMemberService.getInstance().setRepository(mock);
		CMS_StatusManagerController.repository = mock;
	}

	/**
	 * @description       Build Campaigns with unique names
	 *
	 * @param count       Number of Campaigns
	 * @param campaignType Campaign Type
	 * @param doInsert    Insert them
	 * @return            `List<Campaign>`
	 */
	public static List<Campaign> createCampaigns(Integer count, String campaignType, Boolean doInsert) {
		List<Campaign> campaigns = new List<Campaign>();
		for (Integer i = 0; i < count; i++) {
			campaigns.add(new Campaign(Name = 'CMS Test ' + campaignType + ' ' + i, Type = campaignType, IsActive = true));
		}
		if (doInsert) {
			insert campaigns;
		}
		return campaigns;
	}

	/**
	 * @description       Current statuses for one Campaign keyed by label
	 *
	 * @param campaignId  Campaign Id
	 * @return            `Map<String, CampaignMemberStatus>`
	 */
	public static Map<String, CampaignMemberStatus> statusesByLabel(Id campaignId) {
		Map<String, CampaignMemberStatus> statuses = new Map<String, CampaignMemberStatus>();
		for (CampaignMemberStatus status : [SELECT Id, Label, IsDefault, HasResponded, SortOrder FROM CampaignMemberStatus WHERE CampaignId = :campaignId]) {
			statuses.put(status.Label, status);
		}
		return statuses;
	}

	/**
	 * @description             Create a Standard User, optionally with the Campaign Member Status Manager permission set
	 *
	 * @param withManagerAccess Assign the permission set
	 * @return                  `User`
	 */
	public static User createUser(Boolean withManagerAccess) {
		Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
		String uniqueKey = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
		User testUser = new User(
			Alias = 'cms' + uniqueKey.left(5),
			Email = 'cms.test.' + uniqueKey + '@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'CMS Test',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_AU',
			ProfileId = standardProfile.Id,
			TimeZoneSidKey = 'Australia/Brisbane',
			Username = 'cms.test.' + uniqueKey + '@example.com.cmstest'
		);
		insert testUser;

		if (withManagerAccess) {
			PermissionSet managerPermissionSet = [SELECT Id FROM PermissionSet WHERE Name = 'CMS_Campaign_Member_Status_Manager' LIMIT 1];
			insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = managerPermissionSet.Id);
		}
		return testUser;
	}
}