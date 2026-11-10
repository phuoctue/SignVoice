# AUTH_MIDDLEWARE Security Report

## Status: MEDIUM

## Findings

`requireAuth`, `requireStaff`, `requirePermission`, and `requireManagement` are centralized in `backend/src/common/middlewares/auth.middleware.ts`. Admin and staff routers register authentication before handlers. Public auth endpoints are intentionally unauthenticated. A complete route-by-route proof was not generated; staff report/stat routes rely on the router-level staff check without an additional permission.

## What's at risk

Any future route mounted outside the protected router or any over-broad staff permission could expose administrative data.

## What's already secure

JWT sessions are checked against `AuthSession`, user activity, password version, and current authorization data.

## Recommendations

Generate a route inventory in CI and require explicit auth classification for every route; add permission checks to sensitive staff report/stat operations.
