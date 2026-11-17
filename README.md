# Campaign Type Member Statuses

**[Changelog](CHANGELOG.md)**

This code was developed for Marketing Admins who want to automate and enforce the Campaign Member Status options for Campaigns of certain types. It was originally written by [Sercante LLC](https://github.com/sercante-llc/protected-campaign-statuses) and maintained by [X-Squared on Demand](https://github.com/x2od/campaign-member-status). This is the SalesFix fork.

> This application is designed to run on the Salesforce Platform

- [Campaign Type Member Statuses](#campaign-type-member-statuses)
- [A solution for Campaign Type Member Statuses](#a-solution-for-campaign-type-member-statuses)
- [Installation Instructions](#installation-instructions)
  - [What You Get](#what-you-get)
  - [Get started](#get-started)
  - [Managing statuses from the Campaign Member Statuses tab](#managing-statuses-from-the-campaign-member-statuses-tab)
  - [Managing statuses in Setup](#managing-statuses-in-setup)
  - [Schedule the nightly repair](#schedule-the-nightly-repair)
  - [Pushing Code to a Sandbox](#pushing-code-to-a-sandbox)
  - [Installing into a Scratch Org](#installing-into-a-scratch-org)
  - [Upgrading from an earlier version](#upgrading-from-an-earlier-version)
- [What's behind the curtain?](#whats-behind-the-curtain)
- [How it Works](#how-it-works)
- [FAQ](#faq)

# A solution for Campaign Type Member Statuses

## Originally written by [Adam Erstelle](https://thespotforpardot.com/author/adamsercante-com/)

We go through all the effort of setting up beautiful Salesforce Campaigns, naming standards and maybe even a hierarchy. The next challenge in completing your beautiful work of campaign art is getting a hold on your Campaign Member Statuses for each campaign.

When a new Salesforce Campaign is created, many people aren't just happy with the two default statuses of Sent and Responded. This prompts them to create what they think makes the most sense. Though as time goes on and as reporting starts to be needed, everyone making their own Campaign Member Statuses can be a nightmare that prevents you from getting meaningful and actionable intelligence. It would be really nice to take the guesswork out of status reporting and have a standard set of Campaign Member Statuses everyone uses consistently.

Jenna Molby posted a [fantastic solution](https://jennamolby.com/how-to-automatically-create-campaign-statuses-in-salesforce/) that enables you to automatically create the right Statuses on Campaign creation. The automation here is good, though as you increase the number of Types the Flow could become a bit unwieldy.

Another thing that could be a problem comes later when other people might make changes to your carefully crafted structure. What happens if someone edits or even removes these statuses?

Campaign Type Member Statuses solves this by automating (and enforcing) Campaign Member Statuses by Type. It allows you to:

1.  Define the Campaign Member Statuses that should always be present on given Campaign Types.
2.  Restore the protected statuses on active Campaigns should someone change them.
3.  Create additional statuses for specific reasons.
4.  Override by authorised users on a per-Campaign basis.
5.  Let trusted marketing users maintain the rules from a tab, without Setup access.

# Installation Instructions

## What You Get

- 1 Custom Metadata Type (`Campaign_Type_Member_Status__mdt`) with page layout and list view
- 1 Campaign custom field (`Protect_Campaign_Member_Statuses__c`)
- 1 Change Data Capture selection (`CampaignMemberStatus`)
- 1 Platform Event (`CMS_Status_Config_Deployed__e`) used by the tab to report when a change has finished saving
- 1 Lightning tab (**Campaign Member Statuses**) and the `cmsStatusManager` Lightning web component behind it
- 1 Custom Permission (`CMS_Manage_Campaign_Member_Statuses`)
- 2 Permission Sets: **Campaign Type Member Status Admin** and **Campaign Member Status Manager**
- 7 Apex classes, 8 Apex test classes, and sample triggers in `unpackaged/triggers-sample`

The Change Data Capture selection uses one of your org's Change Data Capture entity slots. Check one is free before deploying.

## Get started

If you install only the core code via the package, you will not have any triggers installed.

1.  Deploy the main directory.

    ```bash
    sf project deploy start --source-dir force-app
    ```

2.  Update your existing trigger handlers, or create new triggers, for the following objects and contexts.

    | **Object**                      | **Context**   | **Apex code**                                              |
    | ------------------------------- | ------------- | ---------------------------------------------------------- |
    | CampaignMemberStatusChangeEvent | after insert  | `new CMS_MemberStatusEventTriggerHandler().afterInsert();` |
    | Campaign                        | before insert | `new CMS_CampaignTriggerHandler().beforeInsert();`         |
    | Campaign                        | after insert  | `new CMS_CampaignTriggerHandler().afterInsert();`          |
    | Campaign                        | before update | `new CMS_CampaignTriggerHandler().beforeUpdate();`         |

    Sample triggers are in [unpackaged/triggers-sample/triggers](unpackaged/triggers-sample/triggers). Both handlers also have a constructor that takes the trigger records directly, for trigger frameworks that pass them in.

3.  Define your protected statuses, either from the [Campaign Member Statuses tab](#managing-statuses-from-the-campaign-member-statuses-tab) or [in Setup](#managing-statuses-in-setup).
4.  [Schedule the nightly repair](#schedule-the-nightly-repair).

Campaigns with Types not set up keep the two default statuses that Salesforce creates. There's no need to add the checkbox field on Campaign to page layouts, but if you do, make it read-only.

## Managing statuses from the Campaign Member Statuses tab

Assign the **Campaign Member Status Manager** permission set to the people who should maintain the rules. It gives them the Campaign Member Statuses tab and the `CMS_Manage_Campaign_Member_Statuses` custom permission. They don't need Customize Application.

```bash
sf org assign permset --name CMS_Campaign_Member_Status_Manager --on-behalf-of user@example.com
```

On the tab:

1.  Choose a Campaign Type. Types that already have protected statuses are marked "(protected)".
2.  Add, rename or remove statuses, tick the one **Default** status, and tick **Responded** where the status counts as a response.
3.  Click **Save**. The change is deployed as custom metadata and usually finishes within a few seconds; the tab tells you when it has.

Things to know:

- **Removing a status stops protecting it.** Custom metadata records can't be deleted from Apex, so the record is marked **Inactive**. The status is not deleted from existing Campaigns.
- **Removing every status stops protecting the Campaign Type.**
- New Campaigns get the new statuses straight away. Existing protected Campaigns pick up changes when one of their statuses is edited, or at the nightly repair.
- Every save is recorded in **Setup > Deployment Status** and the **Setup Audit Trail** under the user's name.
- The permission is checked on the server for every request, and input is validated on the server too. Hiding the tab is not the only control.
- Only assign the permission set to people trusted to change org-wide marketing configuration.

## Managing statuses in Setup

Administrators can still manage the records directly.

1.  In Setup, go to Custom Metadata Types and click **Manage Records** for Campaign Type Member Status.

    ![Campaign Type Member Status](doc-assets/assets/Campaign-Member-Statuses-1.png)

2.  Click **New**.

    ![Campaign Type Member Status](doc-assets/assets/Campaign-Member-Statuses-2.png)

3.  Fill in the fields.

    - `Label`: shown in the list of records. Recommended convention: TYPE-STATUS
    - `Name`: API name. Let it autofill from the Label.
    - `Campaign Type`: the value of the Campaign's Type field. Matching ignores capitalisation.
    - `Member Status`: the status that becomes protected.
    - `Is Default`: the default status. If more than one record for a Type is ticked, only the first is used; if none is ticked, the first status becomes the default.
    - `Responded`: tick if this status counts as Responded.
    - `Inactive`: tick to stop protecting this status without deleting the record.

    ![Campaign Type Member Statuses](doc-assets/assets/Campaign-Member-Statuses-3.png)

4.  Click **Save** (or **Save & New**) and repeat.

## Schedule the nightly repair

The nightly job restores protected statuses that were deleted and corrects Default and Responded settings. It runs as a batch, so it handles any number of Campaigns.

Run this once as anonymous Apex (schedules it for 2:00 am daily in your time zone):

```apex
CampaignMemberStatusJob.scheduleDaily();
```

Or, in Setup, go to Apex Classes and click **Schedule Apex**, choose `CampaignMemberStatusJob`, and run it daily during off-peak hours.

![Campaign Type Member Statuses](doc-assets/assets/Campaign-Member-Statuses-5.png)

## Pushing Code to a Sandbox

1. Clone this repository

   ```bash
   git clone https://github.com/SalesFix/campaign-member-status.git
   cd campaign-member-status
   ```

1. [Install the Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm)

1. Authorise your sandbox and give it an alias (**myorg** below)

   ```bash
   sf org login web --set-default --alias myorg --instance-url https://test.salesforce.com
   ```

   For orgs with a My Domain URL:

   ```bash
   sf org login web --set-default --alias myorg --instance-url https://mycustomdomain.my.salesforce.com
   ```

1. Deploy the main code, the sample triggers (change them to fit your trigger framework) and, optionally, the sample custom metadata

   ```bash
   sf project deploy start --source-dir force-app
   sf project deploy start --source-dir unpackaged/triggers-sample
   sf project deploy start --source-dir unpackaged/email-sample
   ```

   Run this command in the terminal to deploy sample statuses for other common Campaign Types. It also adds `Content / White Paper`, `Event`, `Media Partner`, `Paid Search`, `Social Media - Organic`, `Social Media - Paid`, `Survey` and `Website` to the Campaign Type picklist.

   ```bash
   sf project deploy start --source-dir unpackaged/campaign-types-sample
   ```

   The default status for each type is in bold. Statuses marked ✓ count as Responded: the member engaged positively. Negative outcomes such as Unsubscribed, Declined, Not Interested and Disqualified don't count, so they don't inflate response rates or campaign influence.

   | Campaign Type           | Member Statuses                                                                                    |
   | ----------------------- | -------------------------------------------------------------------------------------------------- |
   | Email (`email-sample`)  | **Sent**, Opened, Clicked ✓, Responded ✓, Unsubscribed                                             |
   | Webinar                 | **Invited**, Registered ✓, Attended ✓, On Demand ✓, No Show ✓, Declined                            |
   | Event                   | **Invited**, Registered ✓, Waitlisted ✓, Attended ✓, No Show ✓, Declined                           |
   | Conference              | **Face To Face** ✓, Content Request ✓, Attended Talk ✓                                             |
   | Trade Show              | **Face To Face** ✓, Content Request ✓, Attended Talk ✓                                             |
   | Content / White Paper   | **Downloaded** ✓, Follow-Up Requested ✓                                                            |
   | Social Media - Organic  | **Clicked**, Form Submitted ✓                                                                      |
   | Social Media - Paid     | **Clicked**, Form Submitted ✓                                                                      |
   | Paid Search             | **Clicked**, Form Submitted ✓                                                                      |
   | Advertisement           | **Clicked**, Form Submitted ✓                                                                      |
   | Website                 | **Visitor** ✓                                                                                      |
   | Media Partner           | **Connected** ✓                                                                                    |
   | Direct Mail             | **Sent**, Delivered, Returned, Responded ✓                                                         |
   | Telemarketing           | **To Call**, No Answer, Left Voicemail, Connected ✓, Meeting Booked ✓, Not Interested, Do Not Call |
   | Referral Program        | **Referred** ✓, Contacted ✓, Qualified ✓, Disqualified                                             |
   | Survey                  | **Sent**, Started, Completed ✓, Opted Out                                                          |

   > The sample's Campaign Type value set lists every value Salesforce ships by default plus the new ones. If your org has its own Campaign Type values, add them to `unpackaged/campaign-types-sample/standardValueSets/CampaignType.standardValueSet-meta.xml` before deploying so they stay active. If a Campaign record type restricts the Type picklist, add the new values to that record type too.

1. Assign the permission sets

   ```bash
   sf org assign permset --name Campaign_Type_Member_Status_Admin
   sf org assign permset --name CMS_Campaign_Member_Status_Manager
   ```

1. Continue with [Get started](#get-started)

## Installing into a Scratch Org

1. Enable Dev Hub in your main org, [install the Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm), and authorise the Dev Hub:

   ```bash
   sf org login web --set-default-dev-hub --alias myhuborg
   ```

1. Clone this repository and run the setup script

   ```bash
   git clone https://github.com/SalesFix/campaign-member-status.git
   cd campaign-member-status
   . scripts/campaignmember-scratchorg.sh
   ```

1. Continue with [Get started](#get-started)

## Upgrading from an earlier version

- `CampaignMemberStatusJob` is now a batch job. If it is already scheduled, either delete the scheduled job before deploying and schedule it again afterwards, or turn on **Allow deployments of components when corresponding Apex jobs are pending or in progress** (Setup > Deployment Settings).
- `CampaignMemberRepository.getGroupedProtectedStatuses()` was replaced by `getAllStatusRecords()`. `CampaignMemberService.getGroupedProtectedStatuses()` now returns Types keyed in lower case. Update any custom code that called these.
- `CampaignMemberService.enforceProtectedStatusesForCampaigns()` now returns a map of error messages by Campaign Id instead of throwing.

# What's behind the curtain?

- **Custom Metadata Types** hold the protected statuses, so they deploy like any other metadata.
- **Campaign custom field** `Protect_Campaign_Member_Statuses__c` is ticked automatically when a Campaign is created with a protected Type. You can clear it to make changes to that Campaign's statuses, but you can't turn protection back on afterwards.
- **Change Data Capture** on CampaignMemberStatus tells us when a status is edited so we can put it right. Salesforce doesn't support triggers on CampaignMemberStatus.
- **Triggers** on Campaign set up new Campaigns; the change event trigger watches for edits.
- **Apex Metadata API** lets the Campaign Member Statuses tab save custom metadata without Setup access.

# How it Works

## New Campaign Created

When a Campaign is created with a Type that has protected statuses, the solution:

1. Ticks "Protect Campaign Member Statuses".
1. Adds the protected statuses, sets the configured default, and removes the statuses Salesforce created automatically that aren't part of the configuration.

If the statuses can't be applied, the Campaign isn't saved and the user sees why. Cloned Campaigns are protected based on their own Type.

## Editing a protected status

When a status on a protected Campaign is edited, the Campaign's protected statuses are checked straight away: missing ones are recreated, and Default and Responded are reset. Refresh the page if you don't see it immediately. Statuses users add for their own reasons are left alone.

## Removing a protected status

Change Data Capture can't tell us which Campaign a deleted status belonged to, so deleted protected statuses are restored by the [nightly repair](#schedule-the-nightly-repair).

# FAQ

## Do you have any suggested statuses?

Of course! Here are a few to get your creative juices flowing.

![Suggested Campaign Member Statuses](doc-assets/assets/CMStatuses.png)

## Why don't you just prevent people from changing protected statuses?

We'd like to. A "before update" and "before delete" trigger would be simplest, but Salesforce doesn't support triggers on CampaignMemberStatus, so we fix things afterwards.

## I get Apex test errors in my own tests that create Campaigns. How can I fix them?

Earlier versions relied on the two statuses Salesforce creates automatically, which tests can't see unless they use `seeAllData=true`. This version doesn't rely on them, so your tests should work without changes. If your tests insert Campaigns with a protected Type, they will now get the protected statuses.
