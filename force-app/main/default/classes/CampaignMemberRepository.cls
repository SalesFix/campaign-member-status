/**
 * @description Reads the `Campaign Type Member Status` custom metadata records.
 * <br>Virtual so tests can supply configuration in memory. Uses `getAll()`, which does not
 * consume SOQL queries. Returns active and inactive records; `CMS_StatusRules` decides which apply.
 *
 * @author      Sercante LLC
 * @since       2022
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public inherited sharing virtual class CampaignMemberRepository {
	/**
	 * @description Return every Campaign Type Member Status record, including inactive ones
	 *
	 * @return      `List<Campaign_Type_Member_Status__mdt>`
	 */
	public virtual List<Campaign_Type_Member_Status__mdt> getAllStatusRecords() {
		return Campaign_Type_Member_Status__mdt.getAll().values();
	}
}