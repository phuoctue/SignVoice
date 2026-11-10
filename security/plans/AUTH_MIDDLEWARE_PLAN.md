# AUTH_MIDDLEWARE Fix Plan

## Changes

- `backend/src/routes/*.routes.ts` — annotate/classify every route as public, authenticated, permanent-account, staff, or admin.
- `backend/src/routes/staff.routes.ts` — confirm and narrow permissions for reports and stats.
- Backend tests — assert 401 for protected routes and 403 for non-staff/non-admin callers.

## New files

- Generated route-auth inventory and regression test helper.

## Verification goals

- [ ] Every user-data route has auth before handler.
- [ ] Every admin route has role/permission enforcement.
- [ ] Route inventory test fails when an unclassified route is added.

## Manual verification (for the human)

- Exercise representative public, user, staff, and admin routes with separate QA identities.
