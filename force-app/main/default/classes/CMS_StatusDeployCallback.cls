/**
 * @description Runs when a deployment started from the Campaign Member Statuses tab finishes, and
 * publishes `CMS_Status_Config_Deployed__e` so the tab can tell the user whether it worked.
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatus
 */
public inherited sharing class CMS_StatusDeployCallback implements Metadata.DeployCallback {
	private static final Integer MAX_MESSAGE_LENGTH = 255;

	@TestVisible
	private static CMS_Status_Config_Deployed__e lastPublished;

	/**
	 * @description         Publish the deployment outcome
	 *
	 * @param result        Deployment result
	 * @param context       Callback context
	 */
	public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
		Boolean succeeded = result != null && result.status == Metadata.DeployStatus.SUCCEEDED;
		CMS_Status_Config_Deployed__e outcome = new CMS_Status_Config_Deployed__e(
			Job_Id__c = result?.id,
			Success__c = succeeded,
			Message__c = succeeded ? null : summariseErrors(result).left(MAX_MESSAGE_LENGTH)
		);
		lastPublished = outcome;
		Database.SaveResult publishResult = EventBus.publish(outcome);
		if (!publishResult.isSuccess()) {
			System.debug(LoggingLevel.ERROR, 'CMS: could not publish deployment outcome: ' + publishResult.getErrors());
		}
	}

	/**
	 * @description   Turn a failed deployment into a short, readable message
	 *
	 * @param result  Deployment result
	 * @return        `String`
	 */
	@TestVisible
	private static String summariseErrors(Metadata.DeployResult result) {
		if (result == null) {
			return 'No deployment result was returned.';
		}
		List<String> problems = new List<String>();
		if (String.isNotBlank(result.errorMessage)) {
			problems.add(result.errorMessage);
		}
		if (result.details != null && result.details.componentFailures != null) {
			for (Metadata.DeployMessage failure : result.details.componentFailures) {
				problems.add(failure.fullName + ': ' + failure.problem);
			}
		}
		return problems.isEmpty() ? 'Deployment ' + String.valueOf(result.status) : String.join(problems, '; ');
	}
}