# Setapp (historical)

SaneBar once shipped through Setapp alongside direct distribution. That lane is
retired: SaneBar is now free, MIT-licensed, and community-maintained.

This folder stays because the `SaneBarSetapp` scheme still builds: it uses the
`com.sanebar.app-setapp` bundle ID and copies `Setapp/setappPublicKey.pem`
(a public key, safe to publish) into the app bundle. Keep the PEM in place if
you build that scheme; ignore this folder entirely for normal contributions —
the plain `SaneBar` scheme is the one that matters.
