/**
 * @description Tests for `CMS_StatusManagerController`: permission gate, validation and the
 * custom metadata records it deploys. Deployments are captured by a mock because
 * `Metadata.Operations.enqueueDeployment` can't run in Apex tests.
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CMS_StatusManagerControllerTest {
	private static final String FAKE_JOB_ID = '0Af' + '0'.repeat(11) + '1';

	/**
	 * @description Captures the deployment instead of running it
	 */
	private class CapturingDeployer extends CMS_StatusManagerController.MetadataDeployer {
		public Metadata.DeployContainer captured;
		public Boolean shouldFail = false;

		public override Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			if (shouldFail) {
				throw new CalloutException('Simulated platform failure');
			}
			captured = container;
			return FAKE_JOB_ID;
		}
	}

	private static String campaignType() {
		for (Schema.PicklistEntry entry : Campaign.Type.getDescribe().getPicklistValues()) {
			if (entry.isActive()) {
				return entry.getValue();
			}
		}
		Assert.fail('Setup: the org needs at least one active Campaign Type picklist value');
		return null;
	}

	private static CapturingDeployer useCapturingDeployer() {
		CapturingDeployer deployer = new CapturingDeployer();
		CMS_StatusManagerController.deployer = deployer;
		return deployer;
	}

	private static CMS_StatusManagerController.StatusInput input(String developerName, String statusName, Boolean isDefault, Boolean hasResponded) {
		CMS_StatusManagerController.StatusInput statusInput = new CMS_StatusManagerController.StatusInput();
		statusInput.developerName = developerName;
		statusInput.status = statusName;
		statusInput.isDefault = isDefault;
		statusInput.hasResponded = hasResponded;
		return statusInput;
	}

	private static Map<String, Object> valuesOf(Metadata.CustomMetadata record) {
		Map<String, Object> valuesByField = new Map<String, Object>();
		for (Metadata.CustomMetadataValue fieldValue : record.values) {
			valuesByField.put(fieldValue.field, fieldValue.value);
		}
		return valuesByField;
	}

	private static Map<String, Metadata.CustomMetadata> deployedByFullName(CapturingDeployer deployer) {
		Map<String, Metadata.CustomMetadata> recordsByName = new Map<String, Metadata.CustomMetadata>();
		for (Metadata.Metadata component : deployer.captured.getMetadata()) {
			recordsByName.put(component.fullName, (Metadata.CustomMetadata) component);
		}
		return recordsByName;
	}

	private static String expectAuraError(String campaignTypeValue, List<CMS_StatusManagerController.StatusInput> statuses) {
		try {
			CMS_StatusManagerController.saveStatuses(campaignTypeValue, statuses);
			Assert.fail('Expected an AuraHandledException');
		} catch (AuraHandledException expected) {
			return expected.getMessage();
		}
		return null;
	}

	@isTest
	private static void shouldRejectUserWhenPermissionMissing() {
		User withoutAccess = CMS_TestDataFactory.createUser(false);

		System.runAs(withoutAccess) {
			Test.startTest();
			try {
				CMS_StatusManagerController.getConfiguration();
				Assert.fail('Users without the custom permission must be refused');
			} catch (AuraHandledException expected) {
				Assert.areEqual(System.Label.CMS_Error_No_Permission, expected.getMessage(), 'The user is told which permission set to ask for');
			}
			Test.stopTest();
		}
	}

	@isTest
	private static void shouldRejectSaveWhenPermissionMissing() {
		User withoutAccess = CMS_TestDataFactory.createUser(false);
		CapturingDeployer deployer = useCapturingDeployer();

		System.runAs(withoutAccess) {
			Test.startTest();
			String message = expectAuraError(campaignType(), new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Sent', true, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_No_Permission, message, 'Saving is checked on the server, not just hidden in the UI');
		}
		Assert.isNull(deployer.captured, 'Nothing is deployed');
	}

	@isTest
	private static void shouldReturnTypesAndStatusesWhenUserHasPermission() {
		String typeValue = campaignType();
		Campaign_Type_Member_Status__mdt inactive = CMS_TestDataFactory.status(typeValue, 'Old', false, false);
		inactive.Inactive__c = true;
		CMS_TestDataFactory.useConfiguration(
			new List<Campaign_Type_Member_Status__mdt>{
				CMS_TestDataFactory.status(typeValue, 'Registered', true, false),
				inactive,
				CMS_TestDataFactory.status('Retired Type', 'Kept', true, false)
			}
		);
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			CMS_StatusManagerController.Configuration config = CMS_StatusManagerController.getConfiguration();
			Test.stopTest();

			Map<String, CMS_StatusManagerController.CampaignTypeOption> optionsByValue = new Map<String, CMS_StatusManagerController.CampaignTypeOption>();
			for (CMS_StatusManagerController.CampaignTypeOption option : config.campaignTypes) {
				optionsByValue.put(option.value, option);
			}
			Assert.areEqual(3, config.statuses.size(), 'All records are returned, including inactive ones');
			Assert.isTrue(optionsByValue.get(typeValue).isConfigured, 'A type with an active status is marked configured');
			Assert.isTrue(optionsByValue.get(typeValue).isPicklistValue, 'Picklist values are flagged');
			Assert.isTrue(optionsByValue.containsKey('Retired Type'), 'A configured type that is no longer in the picklist is still listed so it can be switched off');
			Assert.isFalse(optionsByValue.get('Retired Type').isPicklistValue, 'It is flagged as not in the picklist');
		}
	}

	@isTest
	private static void shouldDeployNewRecordsWhenTypeConfiguredForFirstTime() {
		String typeValue = campaignType();
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		CapturingDeployer deployer = useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String jobId = CMS_StatusManagerController.saveStatuses(
				typeValue.toUpperCase(),
				new List<CMS_StatusManagerController.StatusInput>{ input(null, ' Registered ', true, false), input(null, 'Attended', false, true) }
			);
			Test.stopTest();

			Assert.areEqual(FAKE_JOB_ID, jobId.left(15), 'The deployment job Id is returned so the tab can track it');
		}
		List<Metadata.Metadata> deployed = deployer.captured.getMetadata();
		Assert.areEqual(2, deployed.size(), 'One record per status');
		for (Metadata.Metadata component : deployed) {
			Metadata.CustomMetadata record = (Metadata.CustomMetadata) component;
			Map<String, Object> values = valuesOf(record);
			Assert.isTrue(record.fullName.startsWith(CMS_StatusManagerController.METADATA_TYPE_NAME + '.'), 'Records belong to the Campaign Type Member Status type');
			Assert.areEqual(typeValue, values.get('Campaign_Type__c'), 'The picklist value is stored as Salesforce spells it');
			Assert.areEqual(false, values.get('Inactive__c'), 'New records are active');
			if (values.get('Campaign_Member_Status__c') == 'Registered') {
				Assert.areEqual(true, values.get('IsDefault__c'), 'Registered is the default, with surrounding spaces trimmed');
			}
		}
	}

	@isTest
	private static void shouldDeactivateRemovedAndSkipUnchangedWhenEditingType() {
		String typeValue = campaignType();
		Campaign_Type_Member_Status__mdt registered = CMS_TestDataFactory.status(typeValue, 'Registered', true, false);
		Campaign_Type_Member_Status__mdt attended = CMS_TestDataFactory.status(typeValue, 'Attended', false, true);
		Campaign_Type_Member_Status__mdt noShow = CMS_TestDataFactory.status(typeValue, 'No Show', false, false);
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>{ registered, attended, noShow });
		CapturingDeployer deployer = useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			CMS_StatusManagerController.saveStatuses(
				typeValue,
				new List<CMS_StatusManagerController.StatusInput>{ input(registered.DeveloperName, 'Registered', true, false), input(attended.DeveloperName, 'Attended', false, false) }
			);
			Test.stopTest();
		}

		Map<String, Metadata.CustomMetadata> deployed = deployedByFullName(deployer);
		String prefix = CMS_StatusManagerController.METADATA_TYPE_NAME + '.';
		Assert.areEqual(2, deployed.size(), 'Only changed records are deployed: ' + deployed.keySet());
		Assert.isFalse(deployed.containsKey(prefix + registered.DeveloperName), 'Unchanged Registered is not redeployed');
		Assert.areEqual(false, valuesOf(deployed.get(prefix + attended.DeveloperName)).get('HasResponded__c'), 'Attended is updated');
		Assert.areEqual(true, valuesOf(deployed.get(prefix + noShow.DeveloperName)).get('Inactive__c'), 'No Show was removed, so it is marked Inactive');
	}

	@isTest
	private static void shouldReuseInactiveRecordWhenStatusAddedBack() {
		String typeValue = campaignType();
		Campaign_Type_Member_Status__mdt oldRecord = CMS_TestDataFactory.status(typeValue, 'Attended', false, true);
		oldRecord.Inactive__c = true;
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>{ oldRecord });
		CapturingDeployer deployer = useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			CMS_StatusManagerController.saveStatuses(typeValue, new List<CMS_StatusManagerController.StatusInput>{ input(null, 'attended', true, true) });
			Test.stopTest();
		}

		Map<String, Metadata.CustomMetadata> deployed = deployedByFullName(deployer);
		String fullName = CMS_StatusManagerController.METADATA_TYPE_NAME + '.' + oldRecord.DeveloperName;
		Assert.areEqual(1, deployed.size(), 'No duplicate record is created');
		Assert.areEqual(false, valuesOf(deployed.get(fullName)).get('Inactive__c'), 'The inactive record is reactivated');
	}

	@isTest
	private static void shouldDeactivateAllWhenNoStatusesSubmitted() {
		String typeValue = campaignType();
		Campaign_Type_Member_Status__mdt registered = CMS_TestDataFactory.status(typeValue, 'Registered', true, false);
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>{ registered });
		CapturingDeployer deployer = useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			CMS_StatusManagerController.saveStatuses(typeValue, new List<CMS_StatusManagerController.StatusInput>());
			Test.stopTest();
		}

		Metadata.CustomMetadata deployed = deployedByFullName(deployer).get(CMS_StatusManagerController.METADATA_TYPE_NAME + '.' + registered.DeveloperName);
		Assert.areEqual(true, valuesOf(deployed).get('Inactive__c'), 'Saving an empty list stops protecting the type');
	}

	@isTest
	private static void shouldRejectSaveWhenNothingChanged() {
		String typeValue = campaignType();
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(typeValue, new List<CMS_StatusManagerController.StatusInput>());
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Nothing_To_Save, message, 'An empty save for an unconfigured type does nothing');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenTypeBlank() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(' ', new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Sent', true, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Type_Required, message, 'A Campaign Type is required');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenTypeUnknown() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError('Definitely Not A Type 123', new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Sent', true, false) });
			Test.stopTest();

			Assert.areEqual(String.format(System.Label.CMS_Error_Type_Invalid, new List<Object>{ 'Definitely Not A Type 123' }), message, 'Only real Campaign Types can be configured');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenStatusBlank() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(campaignType(), new List<CMS_StatusManagerController.StatusInput>{ input(null, '  ', true, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Status_Required, message, 'Every status needs a name');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenStatusTooLong() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);
		String tooLong = 'S'.repeat(CMS_StatusManagerController.MAX_STATUS_LENGTH + 1);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(campaignType(), new List<CMS_StatusManagerController.StatusInput>{ input(null, tooLong, true, false) });
			Test.stopTest();

			Assert.isTrue(message.startsWith(System.Label.CMS_Error_Status_Too_Long.substringBefore('{0}')), 'Status names are limited to 255 characters');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenStatusDuplicated() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(
				campaignType(),
				new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Attended', true, false), input(null, 'ATTENDED', false, false) }
			);
			Test.stopTest();

			Assert.areEqual(String.format(System.Label.CMS_Error_Duplicate_Status, new List<Object>{ 'ATTENDED' }), message, 'Names must be unique, ignoring case');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenTwoDefaults() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(
				campaignType(),
				new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Registered', true, false), input(null, 'Attended', true, true) }
			);
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Exactly_One_Default, message, 'Two defaults are rejected');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenNoDefault() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(campaignType(), new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Registered', false, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Exactly_One_Default, message, 'A default is required');
		}
	}

	@isTest
	private static void shouldRejectSaveWhenRecordBelongsToAnotherType() {
		String typeValue = campaignType();
		Campaign_Type_Member_Status__mdt otherTypeRecord = CMS_TestDataFactory.status('Some Other Type', 'Registered', true, false);
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>{ otherTypeRecord });
		CapturingDeployer deployer = useCapturingDeployer();
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(typeValue, new List<CMS_StatusManagerController.StatusInput>{ input(otherTypeRecord.DeveloperName, 'Hijacked', true, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Unknown_Record, message, 'A record can only be edited through its own Campaign Type');
		}
		Assert.isNull(deployer.captured, 'Nothing is deployed');
	}

	@isTest
	private static void shouldReturnFriendlyErrorWhenDeploymentCannotStart() {
		CMS_TestDataFactory.useConfiguration(new List<Campaign_Type_Member_Status__mdt>());
		CapturingDeployer deployer = useCapturingDeployer();
		deployer.shouldFail = true;
		User manager = CMS_TestDataFactory.createUser(true);

		System.runAs(manager) {
			Test.startTest();
			String message = expectAuraError(campaignType(), new List<CMS_StatusManagerController.StatusInput>{ input(null, 'Registered', true, false) });
			Test.stopTest();

			Assert.areEqual(System.Label.CMS_Error_Deploy_Failed, message, 'Platform details are not shown to the user');
		}
	}

	@isTest
	private static void shouldGenerateValidDeveloperNameWhenNameHasSymbols() {
		Set<String> used = new Set<String>();

		Test.startTest();
		String generated = CMS_StatusManagerController.generateDeveloperName('1st Party Event!', 'Attended — In Person', used);
		Test.stopTest();

		Assert.isTrue(Pattern.matches('[A-Za-z][A-Za-z0-9_]{0,39}', generated), 'Starts with a letter, letters/numbers/underscores only, 40 characters max: ' + generated);
		Assert.isFalse(generated.contains('__'), 'No double underscores: ' + generated);
		Assert.isFalse(generated.endsWith('_'), 'No trailing underscore: ' + generated);
	}

	@isTest
	private static void shouldAddSuffixWhenDeveloperNameTaken() {
		Set<String> used = new Set<String>{ 'webinar_attended' };

		Test.startTest();
		String generated = CMS_StatusManagerController.generateDeveloperName('Webinar', 'Attended', used);
		Test.stopTest();

		Assert.areEqual('Webinar_Attended_1', generated, 'A numeric suffix keeps the name unique');
	}

	@isTest
	private static void shouldTruncateDeveloperNameWhenTooLong() {
		Set<String> used = new Set<String>();

		Test.startTest();
		String generated = CMS_StatusManagerController.generateDeveloperName('A'.repeat(30), 'B'.repeat(30), used);
		Test.stopTest();

		Assert.isTrue(generated.length() <= 40, 'DeveloperNames are at most 40 characters: ' + generated.length());
	}
}