/**
 * @description In-memory configuration for tests, so tests don't depend on the custom metadata
 * records deployed to the org.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
public without sharing class CampaignMemberRepositoryMocks {
	/**
	 * @description Repository that returns a fixed list of configuration records
	 */
	public class ConfiguredMock extends CampaignMemberRepository {
		private List<Campaign_Type_Member_Status__mdt> configRecords;

		/**
		 * @description         Constructor
		 *
		 * @param configRecords Records to return
		 */
		public ConfiguredMock(List<Campaign_Type_Member_Status__mdt> configRecords) {
			this.configRecords = configRecords == null ? new List<Campaign_Type_Member_Status__mdt>() : configRecords;
		}

		/**
		 * @description Return the configured records
		 *
		 * @return      `List<Campaign_Type_Member_Status__mdt>`
		 */
		public override List<Campaign_Type_Member_Status__mdt> getAllStatusRecords() {
			return configRecords;
		}
	}
}