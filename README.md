# SBC5 Control Center — Release Candidate Channel

> **TEST / EXPERIMENTAL — not a stable SBC5 release**

This repository is the opt-in RC distribution channel for both:

- Home Assistant Apps: `sbc5_control_center_rc/` (experimental App, manual startup, fan-control guard)
- HACS: `custom_components/sbc5_control_center/` (the same integration domain; **do not install stable and RC copies in HACS at the same time**)

## Automatic release pipeline

`.github/workflows/sync-rc.yml` builds directly from the pinned `.rc-source.json` source branch, checks integrity and regression tests, publishes application and integration files on the default branch, and creates an **RC GitHub prerelease**, not a stable release. It never merges or publishes to the stable repositories.

The default branch may initially contain only channel metadata until the first successful sync workflow finishes.

## Home Assistant App setup

Go to **Settings → Apps → Install App → ⋮ → Repositories**, add

`https://github.com/krlmdfk/sbc5-control-center-rc`

and refresh the App Store. The app is labelled **SBC5 Control Center RC** and has **manual boot**.

**Do not run it together with stable SBC5!** Before authorizing the RC App, stop the stable SBC5 App, turn off its automatic startup, and make a Home Assistant backup. The RC App starts with `rc_exclusive_ack: false` and refuses to start until you explicitly change it to `true`. It checks Supervisor's installed-App states on startup and periodically and refuses/exits if stable SBC5 is running. This guard is defense in depth, not a cross-container lock enforced by stable SBC5.

**Data warning:** The RC App has its own `/data` volume. It does not automatically inherit the stable App's trained AI model or fan profile. The RC may write shared Home Assistant configuration, so a full backup and a documented rollback are required before tests.

## HACS setup

You may add this repository under HACS → ⋮ → Custom repositories → Integration. RC GitHub releases are prereleases; enable prerelease/beta versions for this repository if necessary.

**There must only be one installed integration domain `sbc5_control_center`.** Do not download the stable and RC integration repositories simultaneously, since both install into `custom_components/sbc5_control_center`. Switch the selected HACS source rather than treating these as two separate integrations.

## Updating the RC channel

Maintainers update `.rc-source.json` to the next tested RC version and source branch. The workflow is run on each commit, on demand and periodically; installed RC App updates are offered by Supervisor when the published `config.yaml` version changes.

No RC is promoted to stable automatically. The stable channels remain untouched.
