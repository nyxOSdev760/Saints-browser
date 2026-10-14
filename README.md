# Saints

A private iOS browser with a real extension layer, a Safari/Firefox-style UI and a lot of customization. Search is DuckDuckGo only. Saints has no telemetry, analytics, crash reporting, accounts or servers.

## Get the IPA

Every push to `master` builds an **unsigned `Saints.ipa`** on GitHub Actions and attaches it to a release (see **Releases**, or the `Saints-ipa` artifact on the workflow run).

You can sideload it with AltStore, SideStore, Sideloadly or TrollStore. These tools sign it with your own Apple ID. Saints needs iOS 16.4 or later.

## Features

**Extensions**
- Installs Firefox `.xpi`, Chrome `.crx` and unpacked `.zip` WebExtensions (Manifest V2 and V3).
- Installs userscripts (`.user.js`, Greasemonkey/Tampermonkey `GM_*` and `GM.*` APIs) and userstyles (`.user.css`, `@-moz-document`).
- To install, paste a link, pick a file in the Files app, or browse to a store. On addons.mozilla.org and the Chrome Web Store, tap **Add to Saints**. On Greasy Fork and UserStyles.world, tap the site's install link.
- Content scripts run in an isolated `WKContentWorld` for each extension.
- Supported APIs: `runtime` (messaging, `getURL`, `onInstalled`), `storage.local/sync/session` with `onChanged`, `tabs`, `scripting`, `i18n`, `alarms`, `notifications`, `action` popups and `onClicked`, and options pages.
- MV3 `declarativeNetRequest` rulesets are compiled into native WebKit content blockers, so ad blockers work.
- Has a built-in editor for writing your own scripts and styles, plus a starter gallery.

**Privacy**
- DuckDuckGo search: standard, Lite or HTML-only. You can set region, safe search and suggestions.
- Blocks trackers, ads and cookie pop-ups using WebKit content rules.
- HTTPS-only mode, tracking-parameter stripping, Global Privacy Control and pop-up blocking.
- Private tabs use a throwaway data store. A Fire button burns all tabs and data.
- Safe Browsing lookups are off. The user agent matches Safari to reduce fingerprinting.

**Customization**
- Address bar at the bottom (Safari) or top (Firefox), with an optional tab strip, hide-on-scroll and swipe-to-switch-tabs.
- Toolbar buttons you can reorder and pick from 14 actions.
- Themes (System, Light, Dark, AMOLED), any accent color, four font styles, and glass, solid or tinted bars with adjustable roundness.
- Home page with gradient, solid or photo wallpapers, dimming, a greeting, a favorites grid and local privacy stats.
- Grid or list tab overview with adjustable columns, default zoom, desktop mode and a custom user agent.

## Building locally

```sh
brew install xcodegen
xcodegen generate
open Saints.xcodeproj
```
