/**
 * @description Server side of the Campaign Member Statuses tab (`cmsStatusManager` LWC).
 * Lets users with the `CMS_Manage_Campaign_Member_Statuses` custom permission maintain the
 * `Campaign_Type_Member_Status__mdt` records without Customize Application.
 * <br><br>Security model:
 * <br>- Every method checks the custom permission on the server, so the tab being hidden is not the only control.
 * <br>- Custom metadata can't be changed with DML, so changes are queued as a metadata deployment
 *   (`Metadata.Operations.enqueueDeployment`). The deployment is recorded in Setup > Deployment
 *   Status and the Setup Audit Trail under the user's name.
 * <br>- Input is validated here, not only in the browser: the Campaign Type must exist, status names
 *   must be present, unique and at most 255 characters, exactly one status is the default, and a
 *   record can only be edited through the Campaign Type it belongs to.
 * <br>- Custom metadata records can't be deleted from Apex, so removed statuses are marked Inactive.
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public with sharing class CMS_StatusManagerController {
	@TestVisible
	private static final String MANAGE_PERMISSION = 'CMS_Manage_Campaign_Member_Statuses';
	@TestVisible
	private static final String METADATA_TYPE_NAME = 'Campaign_Type_Member_Status';
	@TestVisible
	private static final Integer MAX_STATUS_LENGTH = 255;
	private static final Integer MAX_DEVELOPER_NAME_LENGTH = 40;
	private static final Integer MAX_RECORD_LABEL_LENGTH = 40;

	@TestVisible
	private static CampaignMemberRepository repository = new CampaignMemberRepository();
	@TestVisible
	private static MetadataDeployer deployer = new MetadataDeployer();

	/**
	 * @description Load the Campaign Types and current configuration for the tab
	 *
	 * @return      `Configuration`
	 * @throws AuraHandledException when the user lacks the custom permission
	 */
	@AuraEnabled
	public static Configuration getConfiguration() {
		assertCanManage();

		Configuration config = new Configuration();
		Map<String, CampaignTypeOption> optionsByKey = new Map<String, CampaignTypeOption>();
		for (Schema.PicklistEntry entry : getActiveCampaignTypes()) {
			CampaignTypeOption option = new CampaignTypeOption(entry.getValue(), entry.getLabel());
			option.isPicklistValue = true;
			optionsByKey.put(CMS_StatusRules.toKey(entry.getValue()), option);
		}

		for (Campaign_Type_Member_Status__mdt configRecord : repository.getAllStatusRecords()) {
			config.statuses.add(new StatusRecord(configRecord));
			String typeKey = CMS_StatusRules.toKey(configRecord.Campaign_Type__c);
			if (String.isBlank(typeKey)) {
				continue;
			}
			if (!optionsByKey.containsKey(typeKey)) {
				// A configured Type that is no longer an active picklist value: still show it so it can be cleaned up.
				optionsByKey.put(typeKey, new CampaignTypeOption(configRecord.Campaign_Type__c.trim(), configRecord.Campaign_Type__c.trim()));
			}
			if (configRecord.Inactive__c != true) {
				optionsByKey.get(typeKey).isConfigured = true;
			}
		}
		config.campaignTypes = optionsByKey.values();
		return config;
	}

	/**
	 * @description         Replace the protected statuses for one Campaign Type and start the deployment.
	 *                      Statuses that were configured but aren't in `statuses` are marked Inactive.
	 *                      An empty list stops protecting the Campaign Type.
	 *
	 * @param campaignType  Campaign Type picklist value
	 * @param statuses      The complete list of statuses this Type should have
	 * @return              `String` metadata deployment job Id; completion is announced by the `CMS_Status_Config_Deployed__e` event
	 * @throws AuraHandledException when the user lacks permission or the input is invalid
	 */
	@AuraEnabled
	public static String saveStatuses(String campaignType, List<StatusInput> statuses) {
		assertCanManage();
		List<StatusInput> inputs = statuses == null ? new List<StatusInput>() : statuses;

		List<Campaign_Type_Member_Status__mdt> allRecords = repository.getAllStatusRecords();
		String canonicalType = resolveCampaignType(campaignType, allRecords);
		List<Campaign_Type_Member_Status__mdt> typeRecords = recordsForType(canonicalType, allRecords);
		validateInputs(inputs, typeRecords);

		Metadata.DeployContainer container = buildDeployment(canonicalType, inputs, typeRecords, allRecords);
		if (container.getMetadata().isEmpty()) {
			throw newAuraException(System.Label.CMS_Error_Nothing_To_Save);
		}

		try {
			return String.valueOf(deployer.deploy(container, new CMS_StatusDeployCallback()));
		} catch (Exception deployException) {
			// Don't return platform internals to the browser.
			System.debug(LoggingLevel.ERROR, 'CMS: metadata deployment could not be queued: ' + deployException.getMessage());
			throw newAuraException(System.Label.CMS_Error_Deploy_Failed);
		}
	}

	private static void assertCanManage() {
		if (!FeatureManagement.checkPermission(MANAGE_PERMISSION)) {
			throw newAuraException(System.Label.CMS_Error_No_Permission);
		}
	}

	private static List<Schema.PicklistEntry> getActiveCampaignTypes() {
		List<Schema.PicklistEntry> activeEntries = new List<Schema.PicklistEntry>();
		for (Schema.PicklistEntry entry : Campaign.Type.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				activeEntries.add(entry);
			}
		}
		return activeEntries;
	}

	// The Type must be an active picklist value, or one that is already configured (so stale
	// configuration can still be switched off). Returns the value as Salesforce stores it.
	private static String resolveCampaignType(String campaignType, List<Campaign_Type_Member_Status__mdt> allRecords) {
		if (String.isBlank(campaignType)) {
			throw newAuraException(System.Label.CMS_Error_Type_Required);
		}
		String typeKey = CMS_StatusRules.toKey(campaignType);
		for (Schema.PicklistEntry entry : getActiveCampaignTypes()) {
			if (CMS_StatusRules.toKey(entry.getValue()) == typeKey) {
				return entry.getValue();
			}
		}
		for (Campaign_Type_Member_Status__mdt configRecord : allRecords) {
			if (CMS_StatusRules.toKey(configRecord.Campaign_Type__c) == typeKey) {
				return configRecord.Campaign_Type__c.trim();
			}
		}
		throw newAuraException(String.format(System.Label.CMS_Error_Type_Invalid, new List<Object>{ campaignType.trim() }));
	}

	private static List<Campaign_Type_Member_Status__mdt> recordsForType(String campaignType, List<Campaign_Type_Member_Status__mdt> allRecords) {
		String typeKey = CMS_StatusRules.toKey(campaignType);
		List<Campaign_Type_Member_Status__mdt> typeRecords = new List<Campaign_Type_Member_Status__mdt>();
		for (Campaign_Type_Member_Status__mdt configRecord : allRecords) {
			if (CMS_StatusRules.toKey(configRecord.Campaign_Type__c) == typeKey) {
				typeRecords.add(configRecord);
			}
		}
		return typeRecords;
	}

	private static void validateInputs(List<StatusInput> inputs, List<Campaign_Type_Member_Status__mdt> typeRecords) {
		Set<String> typeDeveloperNames = new Set<String>();
		for (Campaign_Type_Member_Status__mdt configRecord : typeRecords) {
			typeDeveloperNames.add(configRecord.DeveloperName);
		}

		Set<String> seenStatusKeys = new Set<String>();
		Integer defaultCount = 0;
		for (StatusInput input : inputs) {
			String statusName = input?.status?.trim();
			if (String.isBlank(statusName)) {
				throw newAuraException(System.Label.CMS_Error_Status_Required);
			}
			if (statusName.length() > MAX_STATUS_LENGTH) {
				throw newAuraException(String.format(System.Label.CMS_Error_Status_Too_Long, new List<Object>{ statusName.left(50) + '...' }));
			}
			if (!seenStatusKeys.add(CMS_StatusRules.toKey(statusName))) {
				throw newAuraException(String.format(System.Label.CMS_Error_Duplicate_Status, new List<Object>{ statusName }));
			}
			if (String.isNotBlank(input.developerName) && !typeDeveloperNames.contains(input.developerName)) {
				// Stops a crafted request editing a record that belongs to another Campaign Type.
				throw newAuraException(System.Label.CMS_Error_Unknown_Record);
			}
			if (input.isDefault == true) {
				defaultCount++;
			}
		}
		if (!inputs.isEmpty() && defaultCount != 1) {
			throw newAuraException(System.Label.CMS_Error_Exactly_One_Default);
		}
	}

	private static Metadata.DeployContainer buildDeployment(
		String campaignType,
		List<StatusInput> inputs,
		List<Campaign_Type_Member_Status__mdt> typeRecords,
		List<Campaign_Type_Member_Status__mdt> allRecords
	) {
		Map<String, Campaign_Type_Member_Status__mdt> typeRecordsByDeveloperName = new Map<String, Campaign_Type_Member_Status__mdt>();
		for (Campaign_Type_Member_Status__mdt configRecord : typeRecords) {
			typeRecordsByDeveloperName.put(configRecord.DeveloperName, configRecord);
		}
		Set<String> usedDeveloperNameKeys = new Set<String>();
		for (Campaign_Type_Member_Status__mdt configRecord : allRecords) {
			usedDeveloperNameKeys.add(configRecord.DeveloperName.toLowerCase());
		}

		// Records explicitly kept by the user.
		Set<String> claimedDeveloperNames = new Set<String>();
		for (StatusInput keptInput : inputs) {
			if (String.isNotBlank(keptInput.developerName)) {
				claimedDeveloperNames.add(keptInput.developerName);
			}
		}

		Metadata.DeployContainer container = new Metadata.DeployContainer();
		for (StatusInput input : inputs) {
			String statusName = input.status.trim();
			String developerName = input.developerName;
			if (String.isBlank(developerName)) {
				// Reuse an unclaimed record with the same status name (for example one removed earlier) rather than duplicating it.
				developerName = findReusableRecord(statusName, typeRecords, claimedDeveloperNames);
			}
			if (String.isBlank(developerName)) {
				developerName = generateDeveloperName(campaignType, statusName, usedDeveloperNameKeys);
			}
			claimedDeveloperNames.add(developerName);

			Campaign_Type_Member_Status__mdt existing = typeRecordsByDeveloperName.get(developerName);
			Boolean isDefault = input.isDefault == true;
			Boolean hasResponded = input.hasResponded == true;
			Boolean unchanged =
				existing != null &&
				existing.Inactive__c != true &&
				existing.Campaign_Member_Status__c.equals(statusName) &&
				existing.IsDefault__c == isDefault &&
				existing.HasResponded__c == hasResponded &&
				existing.Campaign_Type__c.equals(campaignType);
			if (!unchanged) {
				container.addMetadata(
					buildRecord(developerName, (campaignType + '-' + statusName).left(MAX_RECORD_LABEL_LENGTH), campaignType, statusName, isDefault, hasResponded, false)
				);
			}
		}

		for (Campaign_Type_Member_Status__mdt configRecord : typeRecords) {
			if (!claimedDeveloperNames.contains(configRecord.DeveloperName) && configRecord.Inactive__c != true) {
				container.addMetadata(
					buildRecord(
						configRecord.DeveloperName,
						configRecord.Label,
						configRecord.Campaign_Type__c,
						configRecord.Campaign_Member_Status__c,
						false,
						configRecord.HasResponded__c == true,
						true
					)
				);
			}
		}
		return container;
	}

	private static String findReusableRecord(String statusName, List<Campaign_Type_Member_Status__mdt> typeRecords, Set<String> claimedDeveloperNames) {
		String statusKey = CMS_StatusRules.toKey(statusName);
		for (Campaign_Type_Member_Status__mdt configRecord : typeRecords) {
			if (!claimedDeveloperNames.contains(configRecord.DeveloperName) && CMS_StatusRules.toKey(configRecord.Campaign_Member_Status__c) == statusKey) {
				return configRecord.DeveloperName;
			}
		}
		return null;
	}

	/**
	 * @description Build a valid, unique custom metadata DeveloperName: letters, numbers and single
	 * underscores, starting with a letter, at most 40 characters.
	 *
	 * @param campaignType          Campaign Type
	 * @param statusName            Status name
	 * @param usedDeveloperNameKeys Lower-case DeveloperNames already in use; the new name is added
	 * @return                      `String`
	 */
	@TestVisible
	private static String generateDeveloperName(String campaignType, String statusName, Set<String> usedDeveloperNameKeys) {
		String base = (campaignType + '_' + statusName).replaceAll('[^A-Za-z0-9]+', '_').replaceAll('_+', '_').removeStart('_');
		if (String.isBlank(base) || !base.left(1).isAlpha()) {
			base = 'CMS_' + base;
		}
		base = trimDeveloperName(base, MAX_DEVELOPER_NAME_LENGTH);

		String candidate = base;
		Integer suffix = 1;
		while (usedDeveloperNameKeys.contains(candidate.toLowerCase())) {
			String suffixText = '_' + String.valueOf(suffix);
			suffix++;
			candidate = trimDeveloperName(base, MAX_DEVELOPER_NAME_LENGTH - suffixText.length()) + suffixText;
		}
		usedDeveloperNameKeys.add(candidate.toLowerCase());
		return candidate;
	}

	private static String trimDeveloperName(String value, Integer maxLength) {
		String trimmed = value.left(maxLength);
		while (trimmed.endsWith('_')) {
			trimmed = trimmed.removeEnd('_');
		}
		return trimmed;
	}

	private static Metadata.CustomMetadata buildRecord(
		String developerName,
		String recordLabel,
		String campaignType,
		String statusName,
		Boolean isDefault,
		Boolean hasResponded,
		Boolean inactive
	) {
		Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
		customMetadata.fullName = METADATA_TYPE_NAME + '.' + developerName;
		customMetadata.label = String.isBlank(recordLabel) ? developerName : recordLabel;
		customMetadata.values.add(fieldValue('Campaign_Type__c', campaignType));
		customMetadata.values.add(fieldValue('Campaign_Member_Status__c', statusName));
		customMetadata.values.add(fieldValue('IsDefault__c', isDefault));
		customMetadata.values.add(fieldValue('HasResponded__c', hasResponded));
		customMetadata.values.add(fieldValue('Inactive__c', inactive));
		return customMetadata;
	}

	private static Metadata.CustomMetadataValue fieldValue(String fieldName, Object value) {
		Metadata.CustomMetadataValue fieldValue = new Metadata.CustomMetadataValue();
		fieldValue.field = fieldName;
		fieldValue.value = value;
		return fieldValue;
	}

	private static AuraHandledException newAuraException(String message) {
		AuraHandledException auraException = new AuraHandledException(message);
		auraException.setMessage(message);
		return auraException;
	}

	/**
	 * @description Wraps `Metadata.Operations.enqueueDeployment`, which can't run in Apex tests, so tests can substitute it
	 */
	public virtual class MetadataDeployer {
		/**
		 * @description     Queue the deployment
		 *
		 * @param container Records to deploy
		 * @param callback  Called when the deployment finishes
		 * @return          `Id` deployment job Id
		 */
		public virtual Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			return Metadata.Operations.enqueueDeployment(container, callback);
		}
	}

	/**
	 * @description Data for the tab
	 */
	public class Configuration {
		/**
		 * @description Active Campaign Type picklist values plus any configured Types no longer in the picklist
		 */
		@AuraEnabled
		public List<CampaignTypeOption> campaignTypes = new List<CampaignTypeOption>();

		/**
		 * @description Every configuration record, including inactive ones
		 */
		@AuraEnabled
		public List<StatusRecord> statuses = new List<StatusRecord>();
	}

	/**
	 * @description A Campaign Type the user can pick
	 */
	public class CampaignTypeOption {
		/**
		 * @description Picklist API value
		 */
		@AuraEnabled
		public String value;

		/**
		 * @description Picklist label
		 */
		@AuraEnabled
		public String label;

		/**
		 * @description True when the Type has active protected statuses
		 */
		@AuraEnabled
		public Boolean isConfigured = false;

		/**
		 * @description False when the Type is configured but no longer an active picklist value
		 */
		@AuraEnabled
		public Boolean isPicklistValue = false;

		/**
		 * @description Constructor
		 *
		 * @param value Picklist API value
		 * @param label Picklist label
		 */
		public CampaignTypeOption(String value, String label) {
			this.value = value;
			this.label = label;
		}
	}

	/**
	 * @description A configuration record as shown on the tab
	 */
	public class StatusRecord {
		/**
		 * @description Custom metadata DeveloperName
		 */
		@AuraEnabled
		public String developerName;

		/**
		 * @description Campaign Type
		 */
		@AuraEnabled
		public String campaignType;

		/**
		 * @description Campaign Member Status name
		 */
		@AuraEnabled
		public String status;

		/**
		 * @description Default status for the Type
		 */
		@AuraEnabled
		public Boolean isDefault;

		/**
		 * @description Counts as Responded
		 */
		@AuraEnabled
		public Boolean hasResponded;

		/**
		 * @description No longer protected
		 */
		@AuraEnabled
		public Boolean inactive;

		/**
		 * @description Build from a custom metadata record
		 *
		 * @param source `Campaign_Type_Member_Status__mdt`
		 */
		public StatusRecord(Campaign_Type_Member_Status__mdt source) {
			this.developerName = source.DeveloperName;
			this.campaignType = source.Campaign_Type__c;
			this.status = source.Campaign_Member_Status__c;
			this.isDefault = source.IsDefault__c == true;
			this.hasResponded = source.HasResponded__c == true;
			this.inactive = source.Inactive__c == true;
		}
	}

	/**
	 * @description A status submitted from the tab
	 */
	public class StatusInput {
		/**
		 * @description DeveloperName of the record being edited; blank for a new status
		 */
		@AuraEnabled
		public String developerName { get; set; }

		/**
		 * @description Campaign Member Status name
		 */
		@AuraEnabled
		public String status { get; set; }

		/**
		 * @description Default status for the Type
		 */
		@AuraEnabled
		public Boolean isDefault { get; set; }

		/**
		 * @description Counts as Responded
		 */
		@AuraEnabled
		public Boolean hasResponded { get; set; }
	}
}