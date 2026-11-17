# Review and Remediation

A peer review and security analysis of the forked repository was completed in November 2026. At the time, the fork was identical to the upstream `x2od/campaign-member-status` project. This page records the findings and what was changed.

## Security Findings

| Id  | Finding                                                                                                                                                                          | Outcome                                                                                                                                          |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| S1  | A Dependabot workflow ran a third-party reusable workflow pinned to `@main`, with write permissions and a personal access token, and auto-merged security updates of any version | Removed with the rest of `.github`                                                                                                               |
| S2  | Renovate configuration was pulled from a third-party preset at run time                                                                                                          | Removed with the rest of `.github`                                                                                                               |
| S3  | The Dev Hub auth URL secret was interpolated directly into a CI shell script                                                                                                     | Removed with the rest of `.github`. Any future CI should pass secrets through environment variables and use a dedicated Dev Hub integration user |
| S4  | GitHub Actions and PMD were not pinned to fixed versions                                                                                                                         | Removed with the rest of `.github`                                                                                                               |
| S5  | `npm audit` reported four advisories (three high, one moderate) in development dependencies                                                                                      | Fixed. Three low-severity Babel advisories remain in the LWC Jest tooling; see [Security](security.md)                                           |
| S6  | README and package links pointed to the upstream maintainer, and the README offered a third-party Heroku "Deploy to Salesforce" button                                           | README rewritten and links repointed; the button was removed                                                                                     |
| S7  | Placeholder CODEOWNERS, a duplicate workflow key, unpinned documentation scripts and HTML injection in the generated docs' search box                                            | The documentation site, its scripts and CODEOWNERS were removed                                                                                  |

## Correctness Findings

| Id  | Finding                                                                                                                                                                                  | Outcome                                                                                                                |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| C1  | A protected Campaign whose Type was no longer configured caused a null pointer error, which also stopped enforcement for every other Campaign in the same change event batch             | Such Campaigns are now skipped                                                                                         |
| C2  | Two default statuses configured for one Type could make the change event handler and Salesforce overwrite each other indefinitely                                                        | Exactly one default per Type is enforced when the rules are read, and the handler ignores its own repairs              |
| C3  | One failing Campaign rolled back enforcement for all Campaigns in the transaction                                                                                                        | Partial-success DML with errors reported per Campaign; a new Campaign that can't be set up is rejected with the reason |
| C4  | The nightly job ran in one transaction and would hit the 10,000-row DML limit with large numbers of Campaigns                                                                            | Converted to a batch of 200 Campaigns per chunk                                                                        |
| C5  | The nightly job couldn't find Campaigns with none of their protected statuses left                                                                                                       | The batch now checks every active protected Campaign                                                                   |
| C6  | Single-status Types always set Responded to true, ignoring the configuration                                                                                                             | The configured Responded value is honoured                                                                             |
| C7  | New Campaign setup assumed exactly two automatic statuses in a fixed order. In tests without `seeAllData`, those statuses aren't visible, so client tests that inserted Campaigns failed | Setup no longer depends on the automatic statuses: it adds the configured ones and removes the rest                    |
| C8  | A clone of an unprotected Campaign of a protected Type wasn't protected                                                                                                                  | Clones are evaluated from their own Type                                                                               |
| C9  | Type and status matching was case-sensitive in some places and not others                                                                                                                | Matching ignores case everywhere                                                                                       |

## Other Changes

- All Apex and triggers moved from API 59.0 to 66.0, with `WITH SYSTEM_MODE` and `AccessLevel.SYSTEM_MODE` stated explicitly.
- Tests rewritten: no `seeAllData` except one deliberate test, bulk tests at 251 records, assertion messages throughout, and a shared test data factory.
- Added the Campaign Member Statuses tab, `CMS_StatusManagerController`, the `Inactive__c` field, the deploy-result platform event, the `CMS_Manage_Campaign_Member_Statuses` custom permission and the Campaign Member Status Manager permission set.
- Repository reduced to the package, the required triggers, the sample configuration and this documentation.

## Open Items

- Confirm a non-admin user can save from the Campaign Member Statuses tab in each target org.
- Write the deployment and user guide (tracked as a GitHub issue).
- Decide whether to reintroduce CI, using the lessons from S1 to S4.
