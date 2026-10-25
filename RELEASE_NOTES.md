# pickle_bailbounty v1.0.3

## Fixes

- Debit bail deposits after eligibility checks and preserve monitor items when placement is rejected.
- Validate bounty assignments, detention, delivery and parole progress on the server.
- Prevent repeated settlements and restrict sensitive player views by role.
- Improve database readiness, disconnect handling and pending settlement recovery.

## Upgrade notes

- Verify ankle-monitor, inventory and economy integration on the target server.
- Payments recorded in an ambiguous paying state require operator reconciliation.

## Package and validation

- The ZIP contains one pickle_bailbounty/ folder with the complete resource, installation files, license and runtime NUI assets where applicable. Unbuilt web/ sources, node_modules/ and Git metadata are excluded.
- Required local NUI scripts and stylesheets were checked before packaging. Prior remediation validation passed targeted mocked regressions and Lua/JavaScript syntax checks; this is not a live FiveM integration test.
- Test the resource with your installed frameworks, inventory, database and other integrations before use. Transactions spanning framework persistence, SQL and local KVP still have crash-recovery boundaries.

Source: [audit remediation PR #2](https://github.com/PickleModsCommunity/pickle_bailbounty/pull/2), branch `fix/audit-remediation`. This release includes the PR changes without merging the PR.
