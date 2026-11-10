# XSS Fix Plan

## Changes

- UI/backend review gate — prohibit raw HTML sinks without a sanitizer.
- CSP plan — remove production `unsafe-inline`.

## New files

- Optional static scan rule for raw HTML sinks.

## Verification goals

- [ ] User-controlled values render as text or sanitized HTML only.
- [ ] CSP blocks inline script execution in production.

## Manual verification (for the human)

- Test public text, notes, and collection names with HTML payloads.
