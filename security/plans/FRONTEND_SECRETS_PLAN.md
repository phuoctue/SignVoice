# FRONTEND_SECRETS Fix Plan

## Changes

- CI/deployment — fail if source maps or secret-like values are present in web artifacts.

## New files

- Optional release-artifact scan script.

## Verification goals

- [ ] Production bundle has no `.map` files.
- [ ] Browser assets contain only public origins/keys.
- [ ] Sensitive calls use backend proxy routes.

## Manual verification (for the human)

- Check deployed asset URLs and browser network requests after each release.
