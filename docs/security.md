# Security

## Summary

The package has two kinds of entry point:

- **Automation** (Campaign trigger, change event trigger, nightly job). It runs in system mode so it can repair every protected Campaign, whoever triggered it.
- **The Campaign Member Statuses tab.** It runs with sharing and is gated by a custom permission checked on the server.

There are no REST, SOAP, Visualforce or guest-facing entry points, no callouts, no dynamic SOQL and no stored credentials.

## Access Model

| Permission set                                                          | Grants                                                                                                                                                                                    | Assign to                                                  |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Campaign Member Status Manager (`CMS_Campaign_Member_Status_Manager`)   | Campaign Member Statuses tab, `CMS_StatusManagerController`, `CMS_Manage_Campaign_Member_Statuses` custom permission, read access to the deploy-result event and the custom metadata type | Marketing users trusted to change org-wide status rules    |
| Campaign Type Member Status Admin (`Campaign_Type_Member_Status_Admin`) | Edit access to `Campaign.Protect_Campaign_Member_Statuses__c` and Campaign edit                                                                                                           | Admins who may switch protection off for a single Campaign |

Users without either permission set are still covered by the automation. They don't need any extra access.

## System Mode and Sharing

| Class                                 | Sharing             | Why                                                                                                                                |
| ------------------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `CampaignMemberService`               | `without sharing`   | Integrity automation. It must see and repair every protected Campaign. The change event trigger runs as the Automated Process user |
| `CampaignMemberStatusJob`             | `without sharing`   | The nightly job must reach every protected Campaign, not only those the scheduling user can see                                    |
| `CMS_StatusManagerController`         | `with sharing`      | User-facing entry point                                                                                                            |
| Handlers, repository, rules, callback | `inherited sharing` | No user-facing entry point of their own                                                                                            |

Every query and DML statement in the system-mode classes states `WITH SYSTEM_MODE` or `AccessLevel.SYSTEM_MODE`. That makes the intent explicit and keeps behaviour the same when the API version moves to 67.0 or later, where user mode becomes the default.

## The Campaign Member Statuses Tab

Changing custom metadata normally needs Customize Application. The tab lets users without it change these rules only, so it is controlled tightly:

- **Server-side permission check.** Both controller methods call `FeatureManagement.checkPermission('CMS_Manage_Campaign_Member_Statuses')` before doing anything. Hiding the tab is not the only control.
- **Server-side validation.** The browser's checks are repeated on the server:
  - the Campaign Type must be an active picklist value or already configured,
  - status names are required, unique for the Type ignoring case, and at most 255 characters,
  - exactly one status is the default,
  - a record can only be changed through the Campaign Type it belongs to, so a crafted request can't edit another Type's rules.
- **Generated names.** DeveloperNames are built server side from letters, numbers and single underscores. Users never supply them.
- **No internal details returned.** Platform errors are written to the debug log; the user sees a custom label.
- **Audit trail.** Each save is a metadata deployment, visible in Setup > Deployment Status and the Setup Audit Trail under the user's name.
- **Scope.** The deployment only ever contains `Campaign_Type_Member_Status__mdt` records.

## Data Handled

The package reads and writes Campaign, `CampaignMemberStatus` and its own custom metadata. It doesn't read Campaign Members, Leads or Contacts, and holds no personal information. The deploy-result event carries a job Id, a success flag and an error summary only.

## Supply Chain

- `.github` workflows, Dependabot and Renovate configuration were removed in November 2026. There is no CI at present, so tests must be run before each deployment (see [Development and Testing](development-and-testing.md)).
- npm dependencies are development tooling only (Prettier and LWC Jest). None are deployed to Salesforce.
- `npm audit` reports three low-severity advisories in Babel, pulled in by `@salesforce/sfdx-lwc-jest` 7.9.0. The fix is only in the 8.0.0 pre-release. They affect local test tooling only.

## Residual Risks and Checks

| Item                              | Action                                                                                                                                                                                          |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Non-admin deployment from the tab | Apex tests can't run a metadata deployment. Confirm a user with only the Manager permission set can save from the tab in each target org before go-live                                         |
| Change Data Capture slot          | The package selects `CampaignMemberStatus` for Change Data Capture, which uses one of the org's entity slots. Confirm one is free                                                               |
| Sample Campaign Type value set    | `unpackaged/campaign-types-sample` includes a `CampaignType` standard value set that replaces the org's Campaign Type picklist if deployed. See [Sample Configuration](sample-configuration.md) |
| Protection can be switched off    | Anyone with edit access to the protect checkbox can switch protection off for a Campaign permanently. Keep that field read-only for most users                                                  |
| Manager permission scope          | Manager users change org-wide marketing configuration. Assign the permission set deliberately and review assignments periodically                                                               |
