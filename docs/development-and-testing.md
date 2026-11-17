# Development and Testing

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) (`sf`)
- Node.js 18 or later, for Prettier and the LWC Jest tests
- A Dev Hub for scratch orgs. Use the SalesFix Dev Hub for SalesFix work, never a client's

```bash
npm install
```

## Deployment Order

The order matters because the triggers and sample records depend on the package.

| Step                       | Command                                                                                                     | Notes                                                                                               |
| -------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 1. Package                 | `sf project deploy start --source-dir force-app --target-org <alias>`                                       | Includes the Change Data Capture selection for `CampaignMemberStatus`                               |
| 2. Triggers                | `sf project deploy start --source-dir unpackaged/triggers-sample --target-org <alias>`                      | Skip if the org's trigger framework calls the handlers instead                                      |
| 3. Sample rules (optional) | `sf project deploy start --source-dir unpackaged/campaign-types-sample/customMetadata --target-org <alias>` | See [Sample Configuration](sample-configuration.md) before deploying anything else from that folder |
| 4. Permission sets         | `sf org assign permset --name CMS_Campaign_Member_Status_Manager --target-org <alias>`                      | Plus `Campaign_Type_Member_Status_Admin` for admins who may switch protection off                   |
| 5. Nightly repair          | Anonymous Apex: `CampaignMemberStatusJob.scheduleDaily();`                                                  | Schedules 2:00 am daily in the running user's time zone                                             |

`sf project deploy start` with no `--source-dir` deploys the package directories in `sfdx-project.json` (`force-app` and `unpackaged/email-sample`) but not the triggers.

### Calling the Handlers from an Existing Trigger Framework

| Object                          | Context       | Apex                                                       |
| ------------------------------- | ------------- | ---------------------------------------------------------- |
| Campaign                        | before insert | `new CMS_CampaignTriggerHandler().beforeInsert();`         |
| Campaign                        | after insert  | `new CMS_CampaignTriggerHandler().afterInsert();`          |
| Campaign                        | before update | `new CMS_CampaignTriggerHandler().beforeUpdate();`         |
| CampaignMemberStatusChangeEvent | after insert  | `new CMS_MemberStatusEventTriggerHandler().afterInsert();` |

Both handlers also accept the trigger records in their constructor for frameworks that pass them in.

### Upgrading an Org with an Earlier Version

- `CampaignMemberStatusJob` is now a batch. If it is already scheduled, delete the scheduled job before deploying and schedule it again afterwards, or turn on **Allow deployments of components when corresponding Apex jobs are pending or in progress** in Deployment Settings.
- `CampaignMemberRepository.getGroupedProtectedStatuses()` is replaced by `getAllStatusRecords()`.
- `CampaignMemberService.getGroupedProtectedStatuses()` now keys Types in lower case.
- `CampaignMemberService.enforceProtectedStatusesForCampaigns()` now returns a map of error messages by Campaign Id instead of throwing.

## Scratch Org Workflow

```bash
sf org create scratch --definition-file config/project-scratch-def.json --target-dev-hub <devhub> --alias cms-dev --duration-days 1 --wait 20
sf config set target-org cms-dev
sf project deploy start --source-dir force-app
sf project deploy start --source-dir unpackaged/triggers-sample
npm run apex:test
```

## Tests

There is no CI pipeline, so run both suites before every deployment.

### Apex

```bash
npm run apex:test
```

| Test class                                             | Covers                                                                                                                                                             |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CampaignTriggerTest`                                  | Protecting new Campaigns, exact statuses, single-status Types, 251-record bulk insert, clones, Type changes, re-enabling, rejection when statuses can't be applied |
| `CampaignMemberServiceTest`                            | Restoring deleted statuses, Responded and Default resets, label capitalisation, extra statuses kept, unconfigured Types skipped, partial failure                   |
| `CMS_MemberStatusEventTriggerHandlerTest`              | End-to-end Change Data Capture repair and the loop guard                                                                                                           |
| `CampaignMemberStatusJobTest`                          | 251-Campaign batch repair, Campaigns with no matching statuses left, inactive Campaigns skipped, scheduling, failure counting                                      |
| `CMS_StatusManagerControllerTest`                      | Permission gate, configuration load, deployments built, inactive records reused, every validation rule, deployment failure                                         |
| `CMS_StatusDeployCallbackTest`                         | Success and failure events, message truncation                                                                                                                     |
| `CMS_StatusRulesTest`                                  | Grouping, single default, duplicates, inactive and incomplete records                                                                                              |
| `CMS_TestDataFactory`, `CampaignMemberRepositoryMocks` | Shared test data and in-memory configuration                                                                                                                       |

Tests don't use `seeAllData`, with one deliberate exception: `CampaignTriggerTest.shouldReplacePlatformDefaultStatusesWhenProtectedCampaignInserted`. Salesforce only shows the Sent and Responded statuses it creates on new Campaigns to tests that can see org data, and this test proves they are replaced.

`Metadata.Operations.enqueueDeployment` can't run in Apex tests, so the controller tests use a capturing mock. Check a real save from the tab manually.

### Lightning Web Component (Jest)

```bash
npm run test:unit
npm run test:unit:coverage
```

`statusRules.test.js` covers the validation and sorting rules. `cmsStatusManager.test.js` covers loading, type selection, editing rows, validation, saving, deployment events, the two-minute fallback and refresh.

### Formatting

```bash
npm run prettier:verify
npm run prettier
```

## Latest Results

Run on 17 November 2026 in a Developer Edition scratch org from the SalesFix Dev Hub, at API 66.0.

| Suite                  | Result          | Coverage     |
| ---------------------- | --------------- | ------------ |
| Apex (`RunLocalTests`) | 71 of 71 passed | 97% org-wide |
| LWC Jest               | 33 of 33 passed | 98% of lines |

| Apex class                                                                                                                                                 | Coverage |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| `CampaignMemberRepository`, `CampaignMemberStatusJob`, `CMS_MemberStatusEventTriggerHandler`, `CMS_StatusDeployCallback`, `CMS_StatusRules`, both triggers | 100%     |
| `CampaignMemberService`, `CMS_CampaignTriggerHandler`, `CMS_StatusManagerController`                                                                       | 97%      |

Salesforce Code Analyzer reported no Critical or High findings in the Apex after the changes. The remaining Moderate findings are thresholds stricter than the project's own PMD settings (parameter count, method length, cyclomatic complexity) and test naming style.
