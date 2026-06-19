This folder is for the active Setapp lane.

SaneBar ships through direct Lemon Squeezy/Sparkle distribution and through
Setapp. Keep the Setapp lane separate from the direct lane: Setapp builds use
the `SaneBarSetapp` scheme, the `com.sanebar.app-setapp` bundle ID, Setapp
Framework access, Setapp-managed updates, and Setapp-managed Pro access.

Keep the Setapp-provided `setappPublicKey.pem` in this folder. The Setapp build
script copies `Setapp/setappPublicKey.pem` into the app bundle at build time.

Before any Setapp upload, verify `.saneprocess`, `ARCHITECTURE.md`, release
notes, licensing copy, reviewer notes, and listing screenshots agree with the
active Setapp lane. The Setapp screenshots are declared in `.saneprocess` and
must come from the owned-site app-in-use assets:

- `docs/images/setapp/sanebar-setapp-01-icon-panel.png`
- `docs/images/setapp/sanebar-setapp-02-second-menu-bar.png`
- `docs/images/setapp/sanebar-setapp-03-touch-id.png`
- `docs/images/setapp/sanebar-setapp-04-browse-icons.png`
- `docs/images/setapp/sanebar-setapp-05-appearance.png`

Then follow the canonical SaneProcess lane:

```bash
./scripts/SaneMaster.rb setapp_package --project "$(pwd)" --app-name SaneBar --scheme SaneBarSetapp
./scripts/SaneMaster.rb setapp_media_sync --app SaneBar
./scripts/SaneMaster.rb setapp_upload --zip /path/to/SaneBar-Setapp.zip --release-notes-file /path/to/setapp-public-notes.txt --review-comments-file /path/to/setapp-private-review-comments.txt
./scripts/SaneMaster.rb setapp_status
```

After media sync, verify `https://setapp.com/apps/sanebar` because the public
Setapp page can lag behind the developer portal media list.

Setapp release notes are public customer copy. Do not put review-team comments,
Setapp process details, icon geometry, archive/signing details, direct-store
licensing/update terms, or placeholders in that field. Put private review
context in `--review-comments-file`, or explicitly use
`--no-review-comments-needed` when there is nothing private to add.

Do not ignore Setapp validation alerts. A package is not ready until the final
ZIP passes strict validation, quarantined launch proof, upload/hosted-archive
byte-match proof, and `setapp_status` shows no action required. Approval is not
release; after manual release, rerun `setapp_status` and confirm the public
Setapp status has moved to released/live.
