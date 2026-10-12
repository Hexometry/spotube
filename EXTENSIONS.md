# Spicetify-style extensions for Spotube

Adds an **Extensions** entry under Settings > Developers. It opens a screen with:

- **Marketplace:** searches GitHub for repositories tagged `spicetify-extensions`, lists the
  `.js` files in each (using the repo's `manifest.json` when it has one) and installs them.
- **Installed:** turn extensions on or off, update, remove, install from a link, and a log.

## How it works

Each enabled extension runs in its own hidden WebView (`flutter_inappwebview`, mobile builds only).
A small compatibility layer (`lib/services/extensions/spicetify_shim.dart`) defines the global
`Spicetify` object and talks to the app through one JavaScript handler.

Supported: `Spicetify.Player` (state, `songchange` / `onplaypause` / `onprogress` events, play, pause,
next, back, seek, volume, shuffle, repeat), `showNotification`, `LocalStorage`, `Keyboard`,
`Topbar.Button` and `Menu.Item` (shown as buttons on the Installed tab), `URI`.

Not supported: the Spotify API (`CosmosAsync`), `addToQueue`, React components, `Platform` internals.
Extensions that need them log an error on the Installed tab.

Track URIs are `spotify:track:<id>` when the track comes from Spotify metadata and `spotube:track:<id>`
otherwise.

## Files

- `lib/services/extensions/` shim, models, GitHub marketplace client
- `lib/provider/extensions/extension_host.dart` runs the WebViews and bridges the player
- `lib/pages/settings/extensions/extensions.dart` the screen
- `lib/collections/routes.dart`, `routes.gr.dart`, `lib/pages/settings/sections/developers.dart`,
  `lib/main.dart` small wiring changes
- `.github/workflows/android-apk-fork.yml` builds an installable APK (Actions tab > Run workflow)

Extensions are third-party code. They can see what is playing and can use the network.
