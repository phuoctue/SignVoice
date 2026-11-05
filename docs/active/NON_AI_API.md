# Non-AI integration contracts

All responses use `{success:true,data:<resource>}` or the existing typed error envelope.
All private ownership comes from the verified JWT, never from JSON input. Schema validation
rejects unknown mutation fields, object/array query values, invalid IDs, invalid ranges and
unescaped regular-expression input. Paged lists use bounded positive integers.

Atomic multi-document changes use MongoDB transactions and require Atlas or a replica set.
The documented local Docker setup must initialize a replica set, retain existing data and
authentication, bind development access to loopback, and provide an authenticated readiness
check. Never silently downgrade an atomic operation to partially applied independent writes.

## User

- GET/PATCH `/users/profile`: flat safe User DTO in data, with `_id` (or existing `id`
  alias), email, displayName,avatarUrl,accountType,isGuest,status,role,permissions,
  customRole metadata, createdAt,updatedAt. Never expose provider credentials/password/reset
  hashes. PATCH displayName/avatarUrl. A local email change additionally requires current
  password and uniqueness; OAuth email editing is rejected with a clear explanation.
- GET/PATCH `/users/settings`: flat settings, owner/IDs/timestamps immutable. Existing
  `theme: LIGHT|DARK|SYSTEM`, `fontSize:12..24`, `notificationsEnabled`, preferences and
  `shareUsageData`; add `highContrast:boolean`, `speechSpeed/speechPitch:0.5..2`,
  `autoSpeak:boolean`, `avatarColor:0..3`. Defaults are existing server defaults plus
  highContrast=false,speed/pitch=1,autoSpeak=false,avatarColor=0.
- GET `/users/data/export`: owned safe profile,settings,favorites,conversations,searchHistory
  and exportedAt. No tokens/passwords or other user's records. Frontend downloads JSON.
- DELETE `/users/data`: clear current user's favorites, conversation/search history and reset
  preferences; retain account identity and return truthful counts. Requires explicit UI confirm.
- DELETE `/users/account`: verified current password for LOCAL; explicit confirmation for
  other types. Refuse deleting the last active administrator. Revoke all sessions, remove owned
  data, anonymize account and mark DELETED. UI clears session only after confirmed success.
- GET `/users/sessions` and DELETE `/users/sessions/:id`: own sessions only, safe metadata,
  no token hashes. Revoking the current family signs the client out. Logout-all uses existing API.
- POST `/auth/change-password`: current/new password, validation, version increment and revoke
  sessions, preserving existing reset-password security contract. OAuth task owns auth files;
  backend developer coordinates a follow-up instead of editing them concurrently.

Incorrect current-password proof for a protected profile/account/password action is a 400
validation failure, preserving the authenticated session and form input. Reserve 401 for
invalid or expired access/session credentials; the client uses it to refresh or sign out.

Guests can persist their own temporary data/preferences and retain it when converted using
the existing convert-guest endpoint; the UI must not claim permanent registration replaced
the guest account. Export/deletion operate only on owned guest data. No cross-account merging.

## Dictionary and favorites

Keep existing dictionary/admin routes but normalize DTO handling explicitly. Public readers
see only published entries in active categories. Real empty results remain empty. Detail
re-fetches selected ID, handles missing/archived records, and only opens actual media URLs.

GET `/favorites` returns data array of favorite DTOs with stable `_id`, `entryId` string,
`entry` safe published dictionary object and dates; top-level pagination `{total,limit,skip}`.
POST requires an existing published entry in an active category; duplicate add is idempotent.
DELETE is idempotent. Counters must match actual favorites under repeated/bulk/account deletion.
`/history` remains the current dictionary-view history, never conversation text.

Category deletion and entry creation/reassignment must share transactional write conflicts:
a category with referencing content cannot be deleted, including concurrent requests.
All avatar/video/thumbnail/image URLs allow only HTTP or HTTPS, never executable schemes.

## Conversations

Dedicated `/conversations` routes store user-entered text; no AI-generated content is created.
DTO: `_id`, `content`, `direction: TEXT|SIGN_TO_SPEECH|SPEECH_TO_TEXT`, `favorite`,
`createdAt`, `updatedAt`. New manual input defaults to TEXT and is labelled Văn bản in UI.
GET collection accepts `page,limit,search,direction,favorite` and returns data
`{items,total,page,pages}`. GET/:id returns owned resource or 404. POST validates nonempty
content up to 10000 chars; PATCH/:id updates content/favorite; DELETE/:id deletes owned
resource; DELETE collection clears current user's records and returns deletedCount.

## Staff/admin

Every alias for dictionary writes must share the same permission, creator and status checks.
Staff may manage their own drafts/rejected entries; higher permission roles follow documented
moderation permissions. No write is permitted merely because a dashboard button is visible.
Staff stats use the server's flat data DTO; frontend must register actual list/detail routes.
Session/account management cannot target an actor with higher permissions. Mutations record
an audit event without credentials. Unsupported report/notification actions must not return
fabricated success; implement real resources if exposed, or expose explicit unavailability.

## State boundary

Active implementation is lib/features, reached through lib/app.dart. Main user integration
must exercise those routes. Per-account async loads carry an epoch/user guard so logout or
account switching cannot restore the previous account's data. Settings/profile mutations are
applied after successful persistence; failures preserve input. Sync is real reload, not a timer.
Selected detail without its original ID must show missing; never select another record silently.

Edit forms must wait for the initial persisted resource before enabling Save. A late load
must never overwrite a dirty draft; failed saves keep the draft/dialog available for retry.
All account-owned follow-up loads and dialogs (including session revocation) capture the
account identity/epoch and discard results after an account change, even after a mutation.
The HTTP/auth layer uses the same session boundary: a stale 401, refresh success/failure or
profile refresh from an earlier session cannot clear/replace the current session or replay
an earlier account's mutation with a new account's credentials. Destructive confirmations
and logout also recheck the captured account epoch before dispatch.
