# Assignment pagination

## Behavior

- Admin and employee Home replace assignments when moving between pages of 10; they never append the whole history. Both have Pending / Overdue / Completed filters. Existing admin search and summary metrics remain.
- All assignment feeds use creation date descending, then UUID descending for deterministic ties. The newest 10 appear first, including completed assignments; older records remain reachable through pagination.
- Pagination controls are hidden when there are at most 10 matching records. They remain available on later pages so the user can return to the previous page.
- Calendar is back to the simple daily list of assignment titles, without status filters or status subtitles. Its daily query remains bounded to 10, with pagination only when needed. Changing day, Home filter or search starts at page 1.
- Employee status uses that employee's milestone confirmations, matching the assignment cards. Supervisors use the assignment-wide status.
- Calendar uses the device's local day boundaries, including daylight-saving changes, with an exclusive end boundary.
- Only the active tab observes its feed. Realtime bursts are coalesced and periodic reconciliation refreshes the current page, not the full history.
- Offset pages reflect current data; if assignments change while paging, their positions can change. Pull to refresh reconciles the current page.

## Activation Order

1. Ensure `admin_content_ownership.sql` is installed. Read-only inspection on 2026-11-05 confirmed ownership columns and invoker-mode admin paging RPCs in the connected project.
2. Run `Supabase/assignment_feed_pagination.sql` in the Supabase SQL Editor **before distributing the new app build**. This script has been tested locally but was not deployed as part of this change.
3. Build and distribute a new iOS version through TestFlight. Existing installed builds do not gain the Swift changes automatically.

The SQL only adds/replaces a read-only `assignments_feed_page` RPC and its execute grants. It does not rewrite assignments, confirmations, accounts or ownership. It uses `SECURITY INVOKER`, preserves existing RLS and grants execution only to authenticated users with approved account access. Existing admin paging RPCs are reused without schema changes. No Android client or push-delivery services are changed.

## Verification

SQL tests reconstruct the schema, RLS and RPCs in an isolated PGlite database with synthetic records. No production rows or account credentials are used.

```sh
PGLITE_PATH=file:///path/to/node_modules/@electric-sql/pglite/dist/index.js node Supabase/tests/assignment_feed_pagination.test.mjs
PGLITE_PATH=file:///path/to/node_modules/@electric-sql/pglite/dist/index.js node Supabase/tests/admin_content_ownership.test.mjs
xcrun swiftc -module-cache-path /private/tmp/soundisco-swift-module-cache SoundiscoApp/Features/Assignments/Models/AssignmentFilter.swift SoundiscoApp/Features/Assignments/Models/AssignmentFeedQuery.swift Tests/AssignmentFeedQueryTests.swift -o /private/tmp/soundisco-feed-query-tests
/private/tmp/soundisco-feed-query-tests
```

Coverage: bounded pages, newest-first ordering, exact 10/11-record boundaries for all three Home filters and both roles, server-side search/status/day filtering, personal completion vs team completion, ownership and RLS, malformed requests, JSON request encoding, local dates and 23/25-hour days. Verification passed: 110 feed checks, 67 ownership regression checks, Swift query tests, Debug Simulator build and unsigned Release iOS build. Pre-existing compiler warnings outside these changes remain.

Security advisors were inspected read-only. They report pre-existing warnings for public-schema extensions, callable definer functions and disabled leaked-password protection; no unrelated security configuration was changed. See [Supabase database linter](https://supabase.com/docs/guides/database/database-linter) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Advisors cannot validate this new RPC until it is deployed.

## Device QA Before TestFlight

- Both roles with exactly 10 and then 11 assignments per Home status: verify controls appear only above 10, move next/previous, search for a record beyond page 1 and change filters.
- Confirm newest-first creation order in Pending / Overdue / Completed, and verify admin creator isolation.
- Employee: completing the employee's last milestone moves that assignment from Pending to Completed after refresh.
- Calendar: select past/future days, confirm there are no status filters or status subtitles, and move between multiple pages only if the day contains more than 10 assignments.
- Confirm an employee's completed assignment appears as completed even if another employee has outstanding milestones.
- Check foreground, push and realtime updates refresh only the current page; switch tabs quickly while a request is in flight.
- Check offline errors and retry, empty states, pull to refresh, large text and narrow devices.

No physical-device performance trace or visual QA was captured for this change. Build and automated tests are not a substitute for those checks.
