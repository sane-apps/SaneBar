This folder is for the dormant Setapp lane.

The current SaneBar release strategy is direct Lemon Squeezy/Sparkle distribution. Setapp materials are retained as lane reference only until Setapp is intentionally reactivated and revalidated.

If Setapp is reactivated, keep the Setapp-provided `setappPublicKey.pem` in this folder. The Setapp build script copies `Setapp/setappPublicKey.pem` into the app bundle at build time.

Before any future Setapp upload, first update `.saneprocess`, `ARCHITECTURE.md`, release notes, licensing copy, and reviewer notes so they agree that Setapp is active. Then follow the canonical SaneProcess lane:

```bash
./scripts/SaneMaster.rb mini_preflight --setapp --gui
./scripts/SaneMaster.rb setapp_verify --zip /path/to/SaneBar-Setapp.zip --release-notes-file /path/to/setapp-public-notes.txt --open-url sanebar://settings
./scripts/SaneMaster.rb setapp_upload --zip /path/to/SaneBar-Setapp.zip --release-notes-file /path/to/setapp-public-notes.txt --runtime-proof-file /path/to/setapp-runtime-proof.json
```

Do not ignore Setapp validation alerts. Error `-412003` is upload-blocking unless `setapp_verify --allow-expected-local-setapp-license` also proves the local Setapp provisioning DB state is `app-not-purchased`, which is expected only for a local machine that is not provisioned for the review build.
