# Sample Configuration

The repository includes sample status rules for 16 Campaign Types (54 records). Use them as a starting point and adjust them to suit each organisation's reporting.

| Folder                                                | Contents                                                       |
| ----------------------------------------------------- | -------------------------------------------------------------- |
| `unpackaged/campaign-types-sample/customMetadata/`    | 49 `Campaign_Type_Member_Status` records for 15 Campaign Types |
| `unpackaged/campaign-types-sample/standardValueSets/` | A `CampaignType` picklist value set with 20 values             |
| `unpackaged/email-sample/customMetadata/`             | 5 records for the Email Campaign Type                          |
| `unpackaged/email-sample/objects/`                    | An "Email" list view on the custom metadata type               |

## The Responded Rule

A status counts as Responded when the member engaged positively. Negative outcomes such as Unsubscribed, Declined, Not Interested, Opted Out and Disqualified don't count, so they don't inflate response rates or campaign influence. On ad and social types, a click alone isn't a response; a submitted form is. On Webinar and Event, No Show counts as Responded because the member registered.

## Rules by Campaign Type

The default status is listed first.

| Campaign Type          | Sample folder           | Default status | Counts as Responded                          | Doesn't count as Responded                                      |
| ---------------------- | ----------------------- | -------------- | -------------------------------------------- | --------------------------------------------------------------- |
| Advertisement          | `campaign-types-sample` | Clicked        | Form Submitted                               | Clicked                                                         |
| Conference             | `campaign-types-sample` | Face To Face   | Attended Talk, Content Request, Face To Face | None                                                            |
| Content / White Paper  | `campaign-types-sample` | Downloaded     | Downloaded, Follow-Up Requested              | None                                                            |
| Direct Mail            | `campaign-types-sample` | Sent           | Responded                                    | Delivered, Returned, Sent                                       |
| Email                  | `email-sample`          | Sent           | Clicked, Responded                           | Opened, Sent, Unsubscribed                                      |
| Event                  | `campaign-types-sample` | Invited        | Attended, No Show, Registered, Waitlisted    | Declined, Invited                                               |
| Media Partner          | `campaign-types-sample` | Connected      | Connected                                    | None                                                            |
| Paid Search            | `campaign-types-sample` | Clicked        | Form Submitted                               | Clicked                                                         |
| Referral Program       | `campaign-types-sample` | Referred       | Contacted, Qualified, Referred               | Disqualified                                                    |
| Social Media - Organic | `campaign-types-sample` | Clicked        | Form Submitted                               | Clicked                                                         |
| Social Media - Paid    | `campaign-types-sample` | Clicked        | Form Submitted                               | Clicked                                                         |
| Survey                 | `campaign-types-sample` | Sent           | Completed                                    | Opted Out, Sent, Started                                        |
| Telemarketing          | `campaign-types-sample` | To Call        | Connected, Meeting Booked                    | Do Not Call, Left Voicemail, Not Interested, No Answer, To Call |
| Trade Show             | `campaign-types-sample` | Face To Face   | Attended Talk, Content Request, Face To Face | None                                                            |
| Webinar                | `campaign-types-sample` | Invited        | Attended, No Show, On Demand, Registered     | Declined, Invited                                               |
| Website                | `campaign-types-sample` | Visitor        | Visitor                                      | None                                                            |

Each Type has exactly one default and no record is inactive.

## Campaign Type Picklist

Some sample Types aren't in Salesforce's default Campaign Type picklist: Content / White Paper, Event, Media Partner, Paid Search, Social Media - Organic, Social Media - Paid, Survey and Website. Campaigns can only use them once they are active picklist values.

The sample value set lists all 20 values: Advertisement, Banner Ads, Conference, Content / White Paper, Direct Mail, Email, Event, Media Partner, Paid Search, Partners, Public Relations, Referral Program, Social Media - Organic, Social Media - Paid, Survey, Telemarketing, Trade Show, Webinar, Website and Other.

> **Warning:** deploying `CampaignType.standardValueSet-meta.xml` replaces the org's whole Campaign Type picklist. Any value not in the file is deactivated. `.forceignore` does not exclude this file, so deploying the `campaign-types-sample` folder as a whole includes it. In an existing org, add the new values in Setup (or add the org's own values to the file first), and deploy only the `customMetadata` folder as shown below. If a Campaign record type limits the Type picklist, add the new values to that record type too.

## Deploying the Samples

Deploy the package first, then the rules only:

```bash
sf project deploy start --source-dir unpackaged/campaign-types-sample/customMetadata --target-org <alias>
sf project deploy start --source-dir unpackaged/email-sample --target-org <alias>
```

Deploy the value set only into a new org or a scratch org where replacing the Campaign Type picklist is intended:

```bash
sf project deploy start --source-dir unpackaged/campaign-types-sample/standardValueSets --target-org <alias>
```

## Changing the Samples After Deployment

- Use the Campaign Member Statuses tab, or Setup > Custom Metadata Types > Campaign Type Member Status > Manage Records.
- To stop protecting a status, mark it Inactive rather than deleting the record. The tab does this automatically.
- New rules apply to new Campaigns straight away. Existing protected Campaigns pick up added statuses and changed Default or Responded settings at the next nightly repair, or straight away when one of their statuses is edited.
