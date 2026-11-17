/**
 * @description Tests for `CMS_MemberStatusEventTriggerHandler`.
 * The end-to-end test requires the sample change event trigger in `unpackaged/triggers-sample` (or your own).
 *
 * @author      SalesFix
 * @since       2026
 * @group       CampaignMemberStatusTests
 */
@isTest
private class CMS_MemberStatusEventTriggerHandlerTest {
	@isTest
	private static void shouldRepairCampaignWhenUserEditsProtectedStatus() {
		Test.enableChangeDataCapture();
		CMS_TestDataFactory.useConfiguration(CMS_TestDataFactory.webinarConfig());
		Campaign camp = CMS_TestDataFactory.createCampaigns(1, CMS_TestDataFactory.WEBINAR, true)[0];
		// Deliver the events from creating the Campaign so only the edit below is processed.
		Test.getEventBus().deliver();

		Test.startTest();
		CampaignMemberStatus registered = CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.REGISTERED);
		registered.HasResponded = true;
		update registered;
		Test.stopTest();

		Assert.isFalse(CMS_TestDataFactory.statusesByLabel(camp.Id).get(CMS_TestDataFactory.REGISTERED).HasResponded, 'The change event handler resets Registered to not Responded');
	}

	@isTest
	private static void shouldDoNothingWhenNoEvents() {
		Test.startTest();
		new CMS_MemberStatusEventTriggerHandler(new List<CampaignMemberStatusChangeEvent>()).afterInsert();
		Test.stopTest();

		Assert.areEqual(0, Limits.getDmlStatements(), 'No events means no work');
	}

	@isTest
	private static void shouldProcessWhenUpdateFromUser() {
		Assert.isTrue(CMS_MemberStatusEventTriggerHandler.shouldProcess('UPDATE', UserInfo.getUserId(), UserInfo.getUserId(), false), 'User edits are processed');
	}

	@isTest
	private static void shouldProcessWhenGapUpdate() {
		Assert.isTrue(CMS_MemberStatusEventTriggerHandler.shouldProcess('GAP_UPDATE', null, UserInfo.getUserId(), true), 'Gap updates still carry record Ids and are processed');
	}

	@isTest
	private static void shouldIgnoreWhenCreate() {
		Assert.isFalse(CMS_MemberStatusEventTriggerHandler.shouldProcess('CREATE', UserInfo.getUserId(), UserInfo.getUserId(), false), 'Creates are ignored');
	}

	@isTest
	private static void shouldIgnoreWhenDelete() {
		Assert.isFalse(
			CMS_MemberStatusEventTriggerHandler.shouldProcess('DELETE', UserInfo.getUserId(), UserInfo.getUserId(), false),
			'Deletes are ignored here and repaired by the nightly job'
		);
	}

	@isTest
	private static void shouldIgnoreWhenEventIsOwnRepair() {
		Assert.isFalse(
			CMS_MemberStatusEventTriggerHandler.shouldProcess('UPDATE', UserInfo.getUserId(), UserInfo.getUserId(), true),
			'Repairs committed by the Automated Process user running this trigger are ignored, which prevents update loops'
		);
	}

	@isTest
	private static void shouldProcessWhenAutomatedProcessHandlesAnotherUsersEdit() {
		Assert.isTrue(
			CMS_MemberStatusEventTriggerHandler.shouldProcess('UPDATE', User.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(11) + '1', UserInfo.getUserId(), true),
			'Edits committed by someone else are processed'
		);
	}
}