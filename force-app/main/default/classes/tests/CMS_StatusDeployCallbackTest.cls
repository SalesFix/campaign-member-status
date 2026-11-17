/**
 * @description Tests for `CMS_StatusDeployCallback`
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CMS_StatusDeployCallbackTest {
	private static final String JOB_ID = '0Af' + '0'.repeat(11) + '1';

	@isTest
	private static void shouldPublishSuccessWhenDeploymentSucceeded() {
		Metadata.DeployResult result = new Metadata.DeployResult();
		result.id = JOB_ID;
		result.status = Metadata.DeployStatus.SUCCEEDED;

		Test.startTest();
		new CMS_StatusDeployCallback().handleResult(result, null);
		Test.stopTest();

		Assert.areEqual(JOB_ID, CMS_StatusDeployCallback.lastPublished.Job_Id__c.left(15), 'The event carries the job Id so the tab can match it');
		Assert.isTrue(CMS_StatusDeployCallback.lastPublished.Success__c, 'Success is reported');
		Assert.isNull(CMS_StatusDeployCallback.lastPublished.Message__c, 'No error message on success');
	}

	@isTest
	private static void shouldPublishFailureMessageWhenComponentFailed() {
		Metadata.DeployMessage failure = new Metadata.DeployMessage();
		failure.fullName = 'Campaign_Type_Member_Status.Webinar_Attended';
		failure.problem = 'Invalid value';
		Metadata.DeployDetails details = new Metadata.DeployDetails();
		details.componentFailures = new List<Metadata.DeployMessage>{ failure };
		Metadata.DeployResult result = new Metadata.DeployResult();
		result.id = JOB_ID;
		result.status = Metadata.DeployStatus.FAILED;
		result.details = details;

		Test.startTest();
		new CMS_StatusDeployCallback().handleResult(result, null);
		Test.stopTest();

		Assert.isFalse(CMS_StatusDeployCallback.lastPublished.Success__c, 'Failure is reported');
		Assert.areEqual(
			'Campaign_Type_Member_Status.Webinar_Attended: Invalid value',
			CMS_StatusDeployCallback.lastPublished.Message__c,
			'The failing record and problem are reported'
		);
	}

	@isTest
	private static void shouldTruncateMessageWhenErrorIsLong() {
		Metadata.DeployResult result = new Metadata.DeployResult();
		result.id = JOB_ID;
		result.status = Metadata.DeployStatus.FAILED;
		result.errorMessage = 'E'.repeat(400);

		Test.startTest();
		new CMS_StatusDeployCallback().handleResult(result, null);
		Test.stopTest();

		Assert.areEqual(255, CMS_StatusDeployCallback.lastPublished.Message__c.length(), 'The message fits the 255 character field');
	}

	@isTest
	private static void shouldReportStatusWhenFailureHasNoDetails() {
		Metadata.DeployResult result = new Metadata.DeployResult();
		result.status = Metadata.DeployStatus.CANCELED;

		Test.startTest();
		String summary = CMS_StatusDeployCallback.summariseErrors(result);
		Test.stopTest();

		Assert.areEqual('Deployment ' + String.valueOf(Metadata.DeployStatus.CANCELED), summary, 'The deployment status is used when there are no error details');
	}

	@isTest
	private static void shouldReportMissingResultWhenResultNull() {
		Test.startTest();
		new CMS_StatusDeployCallback().handleResult(null, null);
		Test.stopTest();

		Assert.isFalse(CMS_StatusDeployCallback.lastPublished.Success__c, 'A missing result is treated as a failure');
		Assert.areEqual('No deployment result was returned.', CMS_StatusDeployCallback.lastPublished.Message__c, 'The user is told why');
	}
}