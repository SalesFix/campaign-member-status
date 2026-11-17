# Architecture

## Overview

The solution keeps the Campaign Member Statuses on each Campaign aligned with rules defined per Campaign Type. Rules live in custom metadata. Four processes apply them:

1. **New Campaign:** the Campaign trigger flags the Campaign as protected and creates its statuses.
2. **Status edited:** a Change Data Capture trigger repairs the Campaign straight away.
3. **Nightly repair:** a batch job restores deleted statuses and corrects settings on every active protected Campaign.
4. **Rule change:** the Campaign Member Statuses tab deploys changed rules as custom metadata.

Salesforce does not support triggers on `CampaignMemberStatus`, so the solution repairs changes after they happen rather than preventing them.

## Components

### Data Model

| Component                                      | Type                         | Purpose                                                                  |
| ---------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------ |
| `Campaign_Type_Member_Status__mdt`             | Custom metadata type         | One record per protected status per Campaign Type                        |
| `Campaign_Type__c`                             | Text (255)                   | Campaign Type picklist value the rule applies to (matched ignoring case) |
| `Campaign_Member_Status__c`                    | Text (255)                   | Status label to protect (matched ignoring case)                          |
| `IsDefault__c`                                 | Checkbox                     | The default status for the Type                                          |
| `HasResponded__c`                              | Checkbox                     | Whether the status counts as Responded                                   |
| `Inactive__c`                                  | Checkbox                     | Stops protecting the status without deleting the record                  |
| `Campaign.Protect_Campaign_Member_Statuses__c` | Checkbox                     | Set automatically on create; marks a Campaign as protected               |
| `CMS_Status_Config_Deployed__e`                | Platform event (high volume) | Tells the tab when a rule deployment has finished                        |

All custom metadata fields are subscriber-controlled, which Apex needs to update them.

### Apex

| Class                                 | Role                                                          |
| ------------------------------------- | ------------------------------------------------------------- |
| `CMS_CampaignTriggerHandler`          | Campaign before insert, after insert and before update logic  |
| `CMS_MemberStatusEventTriggerHandler` | `CampaignMemberStatusChangeEvent` handler                     |
| `CampaignMemberService`               | Applies and enforces statuses; one instance per transaction   |
| `CampaignMemberRepository`            | Reads the custom metadata with `getAll()` (no SOQL used)      |
| `CMS_StatusRules`                     | Normalises the rules so every process reads them the same way |
| `CampaignMemberStatusJob`             | Schedulable and batch nightly repair                          |
| `CMS_StatusManagerController`         | Server side of the Campaign Member Statuses tab               |
| `CMS_StatusDeployCallback`            | Publishes the deployment result as a platform event           |

### User Interface and Access

| Component                             | Purpose                                                         |
| ------------------------------------- | --------------------------------------------------------------- |
| `cmsStatusManager`                    | Lightning web component for the tab                             |
| `CMS_Status_Manager`                  | Lightning tab, labelled Campaign Member Statuses                |
| `CMS_Manage_Campaign_Member_Statuses` | Custom permission checked by the controller                     |
| `CMS_Campaign_Member_Status_Manager`  | Permission set: tab, controller, custom permission, event read  |
| `Campaign_Type_Member_Status_Admin`   | Permission set: edit access to the protect checkbox on Campaign |
| Custom labels (`CMS_*`)               | All user-facing error messages                                  |

### Outside the Package

| Component                                                | Why it sits outside                                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `CampaignTrigger`, `CampaignMemberStatusEventTrigger`    | Orgs with a trigger framework call the handlers from their own triggers instead                                          |
| Change Data Capture selection for `CampaignMemberStatus` | In the package as `ChangeEvents_CampaignMemberStatusChangeEvent`; uses one of the org's Change Data Capture entity slots |

## Configuration Rules

`CMS_StatusRules` turns the raw custom metadata into the configuration every process uses:

- Inactive records, and records missing a Type or status, are ignored.
- Types and status names are trimmed and compared ignoring case.
- Each Type has exactly one default. If several records are marked default, the first in sort order wins. If none are, the first status becomes the default.
- Duplicate status names within a Type are ignored after the first.
- Sort order is: default first, then Responded statuses, then alphabetical.

Normalising in one place means a configuration mistake, such as two defaults for one Type, can't make two processes disagree and keep overwriting each other.

## Processes

### New Campaign

1. **Before insert:** if the Type has rules, the protect checkbox is ticked. A user ticking it themselves on create is rejected. Clones are re-evaluated from their own Type.
2. **After insert:** for protected Campaigns, `applyProtectedStatusesToNewCampaigns`:
   1. inserts every configured status that is missing,
   2. sets the configured default (Salesforce clears the previous default itself),
   3. deletes the statuses Salesforce created automatically that aren't in the rules.
3. If a Campaign's statuses can't be applied, that Campaign is rejected with the reason. Other Campaigns in the same save are unaffected.

All work runs as three bulk DML statements (insert, update, delete) for any number of Campaigns.

### Status Edited

1. Salesforce publishes a `CampaignMemberStatusChangeEvent`.
2. `CMS_MemberStatusEventTriggerHandler` processes `UPDATE` and `GAP_UPDATE` events, finds their Campaigns and calls `enforceProtectedStatusesForCampaigns`.
3. Missing statuses are recreated and Label, Default and Responded are reset. Extra statuses users added are left alone.
4. Events committed by the Automated Process user that runs the trigger are skipped, so a repair can never set off another repair.

Delete events don't say which Campaign the status belonged to, so deletions are left to the nightly repair.

### Nightly Repair

1. `CampaignMemberStatusJob.execute(SchedulableContext)` starts the batch, 200 Campaigns per chunk.
2. The batch selects active, protected Campaigns whose Type still has rules.
3. Each chunk runs the same enforcement as the change event handler.
4. Failures are counted and written to the debug log; the job carries on.

`CampaignMemberStatusJob.scheduleDaily()` schedules it for 2:00 am in the scheduling user's time zone.

### Rule Change from the Tab

1. The tab loads the active Campaign Type picklist values and every rule record from `getConfiguration`.
2. The user edits the statuses for one Type. The tab validates them before saving.
3. `saveStatuses` checks the custom permission, validates again, and builds a `Metadata.DeployContainer`:
   - changed or new statuses are upserted,
   - unchanged records are skipped,
   - statuses removed by the user are marked Inactive,
   - a new status that matches an existing inactive record reuses it.
4. `Metadata.Operations.enqueueDeployment` queues the deployment and returns its Id.
5. When it finishes, `CMS_StatusDeployCallback` publishes `CMS_Status_Config_Deployed__e` with the job Id and result.
6. The tab, subscribed through `lightning/empApi`, matches the job Id, shows the result and reloads. If no event arrives within two minutes, it stops waiting and tells the user to check Deployment Status.

## Design Decisions

| Decision                             | Reason                                                                                               |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Custom metadata, not a custom object | Rules deploy between orgs with the rest of the configuration and are cached by Salesforce            |
| Deactivate instead of delete         | Apex can create and update custom metadata records but can't delete them                             |
| Only ever set `IsDefault` to true    | Salesforce clears the old default itself, so a Campaign never passes through a state with no default |
| Fresh records for updates            | Re-saving a queried status would re-send its old `IsDefault` value and could undo the new default    |
| New statuses start at SortOrder 3    | Avoids clashing with the two statuses Salesforce creates, even when tests can't see them             |
| Partial-success DML                  | One bad Campaign can't stop the others being repaired                                                |
| Batch for the nightly repair         | Handles any number of Campaigns within governor limits                                               |
| Platform event for deploy results    | The tab can't query deployment status without a callout                                              |
| Triggers outside the package         | Orgs keep one trigger per object in their own framework                                              |

## Limits and Known Behaviour

- Deleted protected statuses are restored at the next nightly run, not immediately.
- Inactive Campaigns aren't repaired by the nightly job. Edits to their statuses are still repaired by the change event handler.
- Removing a status from the rules stops protecting it. It isn't deleted from existing Campaigns.
- Clearing the protect checkbox on a Campaign stops enforcement for that Campaign. It can't be turned back on.
- The Type of a protected Campaign can't be changed.
