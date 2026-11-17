/**
 * @description Pure rules that turn raw `Campaign_Type_Member_Status__mdt` records into a
 * consistent configuration. Every consumer (triggers, change event handler, nightly job and
 * the Campaign Member Statuses tab) reads configuration through these rules, so they all agree.
 * <br>Rules applied:
 * <br>- Inactive records and records missing a Campaign Type or status are ignored.
 * <br>- Campaign Types and status names are matched case-insensitively.
 * <br>- Each Campaign Type has exactly one default status. If several are marked default, the
 * first in sort order wins; if none are, the first status becomes the default. This stops two
 * "default" records from fighting each other in an endless update loop.
 * <br>- Duplicate status names within a Campaign Type are ignored after the first.
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public inherited sharing class CMS_StatusRules {
	/**
	 * @description Normalise a Campaign Type or status name for case-insensitive comparison
	 *
	 * @param value Raw text
	 * @return      `String` trimmed, lower-case value, or null when the input is null
	 */
	public static String toKey(String value) {
		return value == null ? null : value.trim().toLowerCase();
	}

	/**
	 * @description Group active configuration records by Campaign Type, applying the rules above
	 *
	 * @param records Raw custom metadata records (active and inactive)
	 * @return        `Map<String, List<Campaign_Type_Member_Status__mdt>>` keyed by `toKey(Campaign Type)`;
	 *                each list is sorted with the single default first
	 * @example
	 * Map<String, List<Campaign_Type_Member_Status__mdt>> statusesByType =
	 *     CMS_StatusRules.groupActiveByType(Campaign_Type_Member_Status__mdt.getAll().values());
	 */
	public static Map<String, List<Campaign_Type_Member_Status__mdt>> groupActiveByType(List<Campaign_Type_Member_Status__mdt> records) {
		Map<String, List<Campaign_Type_Member_Status__mdt>> statusesByType = new Map<String, List<Campaign_Type_Member_Status__mdt>>();
		if (records == null || records.isEmpty()) {
			return statusesByType;
		}

		List<Campaign_Type_Member_Status__mdt> activeRecords = new List<Campaign_Type_Member_Status__mdt>();
		for (Campaign_Type_Member_Status__mdt rawRecord : records) {
			if (isUsable(rawRecord)) {
				activeRecords.add(copyOf(rawRecord));
			}
		}
		activeRecords.sort(new StatusOrder());

		Map<String, Set<String>> statusKeysByType = new Map<String, Set<String>>();
		for (Campaign_Type_Member_Status__mdt activeRecord : activeRecords) {
			String typeKey = toKey(activeRecord.Campaign_Type__c);
			if (!statusesByType.containsKey(typeKey)) {
				statusesByType.put(typeKey, new List<Campaign_Type_Member_Status__mdt>());
				statusKeysByType.put(typeKey, new Set<String>());
			}
			// Set.add returns false when the status name is already present for this type.
			if (statusKeysByType.get(typeKey).add(toKey(activeRecord.Campaign_Member_Status__c))) {
				statusesByType.get(typeKey).add(activeRecord);
			}
		}

		for (List<Campaign_Type_Member_Status__mdt> typeStatuses : statusesByType.values()) {
			applySingleDefault(typeStatuses);
		}
		return statusesByType;
	}

	private static Boolean isUsable(Campaign_Type_Member_Status__mdt candidate) {
		return candidate != null && candidate.Inactive__c != true && String.isNotBlank(candidate.Campaign_Type__c) && String.isNotBlank(candidate.Campaign_Member_Status__c);
	}

	// Work on copies so normalising never changes records cached by getAll() for the rest of the transaction.
	private static Campaign_Type_Member_Status__mdt copyOf(Campaign_Type_Member_Status__mdt source) {
		Campaign_Type_Member_Status__mdt copy = new Campaign_Type_Member_Status__mdt();
		copy.DeveloperName = source.DeveloperName;
		copy.Label = source.Label;
		copy.Campaign_Type__c = source.Campaign_Type__c.trim();
		copy.Campaign_Member_Status__c = source.Campaign_Member_Status__c.trim();
		copy.IsDefault__c = source.IsDefault__c == true;
		copy.HasResponded__c = source.HasResponded__c == true;
		copy.Inactive__c = false;
		return copy;
	}

	private static void applySingleDefault(List<Campaign_Type_Member_Status__mdt> typeStatuses) {
		Boolean defaultAssigned = false;
		for (Campaign_Type_Member_Status__mdt status : typeStatuses) {
			if (status.IsDefault__c && !defaultAssigned) {
				defaultAssigned = true;
			} else {
				status.IsDefault__c = false;
			}
		}
		if (!defaultAssigned && !typeStatuses.isEmpty()) {
			typeStatuses[0].IsDefault__c = true;
		}
	}

	/**
	 * @description Sorts by Campaign Type, then default first, then responded first, then status name
	 */
	public class StatusOrder implements Comparator<Campaign_Type_Member_Status__mdt> {
		/**
		 * @description Compare two configuration records
		 *
		 * @param first  First record
		 * @param second Second record
		 * @return       `Integer` negative, zero or positive
		 */
		public Integer compare(Campaign_Type_Member_Status__mdt first, Campaign_Type_Member_Status__mdt second) {
			Integer result = CMS_StatusRules.toKey(first.Campaign_Type__c).compareTo(CMS_StatusRules.toKey(second.Campaign_Type__c));
			if (result == 0) {
				result = compareFlags(first.IsDefault__c, second.IsDefault__c);
			}
			if (result == 0) {
				result = compareFlags(first.HasResponded__c, second.HasResponded__c);
			}
			if (result == 0) {
				result = CMS_StatusRules.toKey(first.Campaign_Member_Status__c).compareTo(CMS_StatusRules.toKey(second.Campaign_Member_Status__c));
			}
			return result;
		}

		private Integer compareFlags(Boolean first, Boolean second) {
			if (first == second) {
				return 0;
			}
			return first ? -1 : 1;
		}
	}
}