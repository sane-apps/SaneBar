This folder is for the active Setapp lane.

Setapp is a third macOS channel, separate from direct Lemon Squeezy/Sparkle distribution and separate from App Store work.

Keep the Setapp-provided `setappPublicKey.pem` in this folder. The Setapp build script copies `Setapp/setappPublicKey.pem` into the app bundle at build time.

Before upload, follow the canonical SaneProcess lane:

```bash
./scripts/SaneMaster.rb mini_preflight --setapp --gui
./scripts/SaneMaster.rb setapp_verify --zip /path/to/SaneBar-Setapp.zip --release-notes-file /path/to/setapp-public-notes.txt --open-url sanebar://settings
./scripts/SaneMaster.rb setapp_upload --zip /path/to/SaneBar-Setapp.zip --release-notes-file /path/to/setapp-public-notes.txt --runtime-proof-file /path/to/setapp-runtime-proof.json
```

Do not ignore Setapp validation alerts. Error `-412003` is upload-blocking unless `setapp_verify --allow-expected-local-setapp-license` also proves the local Setapp provisioning DB state is `app-not-purchased`, which is expected only for a local machine that is not provisioned for the review build.
