# Campaign Member Status Protection

A Salesforce package that gives every Campaign the right Campaign Member Statuses for its Type, and keeps them that way.

Maintained by SalesFix, a Salesforce Consulting Partner. Built on the open-source [campaign-member-status](https://github.com/x2od/campaign-member-status) project by Sercante LLC and X-Squared on Demand, under the MIT licence.

## What It Does

- **Sets up new Campaigns automatically.** When a Campaign is created with a configured Type, it gets exactly the statuses defined for that Type, with the right default and the right Responded settings.
- **Repairs changes.** If someone edits a protected status, it is put back straight away. If someone deletes one, the nightly repair job restores it.
- **Lets marketing teams own the rules.** The Campaign Member Statuses tab lets trusted users change the rules without Setup access or Customize Application.
- **Leaves room for extras.** Users can still add their own statuses to a Campaign; only the protected ones are enforced.

## Repository Layout

| Path                                | What it holds                                                                                                                                                           |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `force-app/`                        | The package: Apex, Lightning web component, tab, custom metadata type, fields, permission sets, platform event and labels                                               |
| `unpackaged/triggers-sample/`       | The two triggers the package needs. Kept outside the package so each org can use its own trigger framework                                                              |
| `unpackaged/campaign-types-sample/` | Sample rules for 15 Campaign Types, plus a sample Campaign Type picklist (read the warning in [Sample Configuration](docs/sample-configuration.md) before deploying it) |
| `unpackaged/email-sample/`          | Sample rules for the Email Campaign Type                                                                                                                                |
| `config/`                           | Scratch org definition                                                                                                                                                  |
| `docs/`                             | Build documentation                                                                                                                                                     |

## Quick Start

```bash
sf project deploy start --source-dir force-app --target-org <alias>
sf project deploy start --source-dir unpackaged/triggers-sample --target-org <alias>
sf project deploy start --source-dir unpackaged/campaign-types-sample/customMetadata --target-org <alias>
sf org assign permset --name CMS_Campaign_Member_Status_Manager --target-org <alias>
```

Then schedule the nightly repair by running this anonymous Apex once:

```apex
CampaignMemberStatusJob.scheduleDaily();
```

Full deployment steps, prerequisites and checks are in [Development and Testing](docs/development-and-testing.md).

## Documentation

| Document                                                   | Read it for                                                                          |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [Architecture](docs/architecture.md)                       | Components, data model, how each process works, and the design decisions behind them |
| [Security](docs/security.md)                               | Permission model, system mode, validation, audit trail and residual risks            |
| [Sample Configuration](docs/sample-configuration.md)       | The sample status rules for each Campaign Type and how to deploy them safely         |
| [Development and Testing](docs/development-and-testing.md) | Local setup, scratch orgs, deployment order, Apex and Jest tests, latest results     |
| [Review and Remediation](docs/review-and-remediation.md)   | The November 2026 peer review findings and what was changed                          |

## Licence

MIT. See [LICENSE](LICENSE). Copyright notices from Sercante LLC and X-Squared on Demand are retained as the licence requires.
