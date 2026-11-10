# FILE_UPLOADS Fix Plan

## Changes

- Avatar service — add dimension/decompression limits if supported by the image pipeline.
- New upload routes — reuse a shared validator and non-public storage policy.

## New files

- Shared upload policy module if a second upload feature is introduced.

## Verification goals

- [ ] Magic bytes, size, dimensions, and ownership are enforced server-side.
- [ ] Stored filenames are server-generated and non-executable.

## Manual verification (for the human)

- Test oversized, malformed, polyglot, and unauthorized avatar requests.
