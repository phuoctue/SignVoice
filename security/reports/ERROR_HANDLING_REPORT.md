# ERROR_HANDLING Security Report

## Status: MEDIUM

## Findings

The global handler in `backend/src/common/middlewares/errorHandler.ts` exists and production responses hide unexpected messages. In development it returns `err.message` and a stack. The local scan also found `/api-docs/` public because the local server runs with development settings; production disables Swagger unless explicitly enabled.

## What's at risk

A misconfigured production `NODE_ENV=development` or `SWAGGER_ENABLED=true` can expose implementation details and a complete API map.

## What's already secure

Production branch of the handler logs details server-side and returns generic unexpected-error text. Unknown routes return structured 404 JSON.

## Recommendations

Fail closed for production configuration, gate API docs behind admin/auth or disable them, and add tests asserting no stack/path leakage in production mode.
