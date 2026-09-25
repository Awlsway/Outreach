# QR-only pairing cleanup

Owner authorized removing manual pairing before publishing the APK. Work is isolated on `codex/qr-pairing-apk`. A local source snapshot including previously uncommitted files was saved under ignored `build/manual-pairing-checkpoint` before deletion. This snapshot is not a GitHub backup and can be lost by cleaning build outputs. No commit or push is claimed; main's committed history is unchanged.

Removed: manual address/code/fingerprint form, standalone certificate-check controls, save/pair/clear buttons, their UI state/controllers/handlers and obsolete application-level test injections. Removed the manual-form portion of widget coverage and its fake transport; retained sync-status and record coverage with assertions that manual controls are absent.

Retained: certificate checking and pinned transport, six-digit exchange/request/response services, secure credential storage, internal pairing persistence/reset methods, worker/device identity, QR parser, outbox, acknowledgement and sync services. These are reusable by QR enrollment or its authorized lifecycle. The term manual sync means the worker taps Sync; it does not mean manual pairing.

Retained historical runbooks and synthetic transport tools as development evidence/regression infrastructure, not product fallback. They do not expose the removed manual form and must not be followed as the current onboarding procedure. Temporary upload review/export tooling is a separate sync-testing concern, not removed as a pairing dependency.

New enrollment is deliberately unavailable until the QR scanner is implemented. Sync status states this explicitly. Existing saved connections and phone data are not erased. No APK build/install or LAN project edit occurred in this cleanup.

References: `36_qr_pairing_v1.md`, `13_dashboard_api_contract.md`.

Validation: 27 focused widget, reusable pairing and QR parser tests passed. `dart analyze lib test` reported no issues.
