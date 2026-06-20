# Share URL Cleaner

A native iOS (SwiftUI) app that strips tracking parameters from URLs you share —
`utm_source`, `fbclid`, `gclid`, and the rest — using [AdGuard's tracking-parameter
filter](https://github.com/AdguardTeam/FiltersRegistry). Native port of the Android
[ShareURLCleaner](../ShareURLCleaner).

## Use it

1. **App** — open the app to set the filter-list URL, tap **Update Now** to download the
   rules, and toggle **Auto Update Daily**. It ships with a small built-in set of common
   trackers so it works before the first download.
2. **Share Extension** — from any app's share sheet (Safari, Notes, …), pick **URL
   Cleaner**. It shows the cleaned URL with **Copy** and **Share…** buttons. (iOS can't
   silently re-share like Android, so you confirm the result.)

Everything runs on-device. The only network request is downloading the filter list; shared
URLs never leave your phone.

## Develop

See [CLAUDE.md](CLAUDE.md) for build commands, the App Group setup, and the logic self-check.
