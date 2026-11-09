# SBC5 RC testing safeguards

- **Do not run Stable and RC Apps simultaneously.** A separate App may otherwise contend for the same PWM fan hardware and host configuration.
- RC App startup is guarded by a deliberate `rc_exclusive_ack: true` setting and a Supervisor check that the stable App is stopped. Without Supervisor access, the RC refuses to run.
- Boot is `manual`. Never set it to `auto` on a device with stable SBC5 installed.
- RC has its **own** persistent `/data` and does not inherit the learned model from Stable. RC is a parallel test environment, not a state-preserving in-place upgrade.
- Both Apps map host Home Assistant configuration. Make a full backup, including the separate SBC5 App data, before testing. A different App slug alone does **not** isolate the shared Home Assistant configuration.
- To test, stop Stable and disable its automatic boot first. Install RC, inspect configuration and only then acknowledge exclusive start. Keep Stable stopped throughout testing.
- If you revert, stop RC, disable its boot, restore the intended shared configuration from backup if modified, then start Stable.
- HACS uses the identical integration domain `sbc5_control_center`, so installing both repositories as separate integrations is NOT supported. Switch the HACS custom repository source deliberately; do not overwrite the stable integration unintentionally.
- Releases are GitHub prereleases and are not promoted or merged to stable automatically.
