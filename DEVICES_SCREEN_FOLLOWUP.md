# Follow-up: Devices / Token Management Screen

Deferred from the Account Login MVP (username + password, shipped 2026-07-15).
This is the optional §5/§6 piece from the auth handoff — a "Signed in as … /
Devices" screen that lists the account's tokens and lets the user revoke them.

## Why it was deferred

The MVP covers login, Keychain token storage, global 401 → login, and
best-effort single-device logout. Listing/revoking *other* devices is a
nice-to-have, not needed for basic sign-in. The groundwork is already in place:
we persist `tokenId`, so revoking the current session already works.

## What exists today

- `SessionStore` — owns the session; already has `signOut()` (revokes the
  current token via `tokenId`, then clears the Keychain).
- `WorkoutAPIClient.fetchMe()` — returns `MeResponse { user, tokens: [AuthToken] }`.
  **Already implemented and wired**, just not surfaced in the UI yet.
- `WorkoutAPIClient.revokeToken(id:)` — `DELETE /api/auth/tokens/{id}`; treats
  204 and 404 as success. Works for any of the account's own tokens.
- `AuthToken` model — `{ id, name, createdAt, lastUsedAt, expiresAt }`.

So the networking layer is done. This is essentially a view + a bit of state.

## Endpoints (from the handoff doc §5/§6)

| Method   | Path                          | Purpose                            |
| -------- | ----------------------------- | ---------------------------------- |
| `GET`    | `/api/auth/me`                | Current user + list of their tokens |
| `DELETE` | `/api/auth/tokens/{tokenId}`  | Revoke a token (this or another device) |

All authenticated (`Authorization: Bearer <token>`). A `DELETE` for a token id
that isn't yours returns `404`, so there's nothing to leak.

## Proposed scope

- New `DevicesView` reached from **Settings → Account** ("Manage devices" row).
- On appear: `session.loadTokens()` → `apiClient.fetchMe()`; show a list of
  `AuthToken`s (name, last used, created; mark the current device using the
  stored `tokenId`).
- Per-row **Revoke** (disabled/hidden for the current device, since that's the
  existing Sign Out): confirmation dialog → `apiClient.revokeToken(id:)` →
  refresh the list.
- Handle the empty/loading/error states; a 401 during load already routes to
  login via the global `.trainingAPIUnauthorized` path.

## Notes / decisions to make

- **Date formatting:** `createdAt` / `lastUsedAt` / `expiresAt` come back as
  ISO-8601 strings — decide on a relative ("2 days ago") vs absolute display.
- **Current-device marking:** compare each `AuthToken.id` against the stored
  `SessionStore.tokenIdKey` value.
- **Revoke-self guard:** revoking the current token should route to login (same
  as Sign Out); simplest to just not offer Revoke on the current row.
- Add a `SessionStore.loadTokens()` / `revoke(tokenId:)` wrapper so the view
  doesn't talk to the actor directly, matching the existing pattern.

See the memory note `project-ios-account-login` and `training-api-repo` for the
full auth architecture and backend context.
