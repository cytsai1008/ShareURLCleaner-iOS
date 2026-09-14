# Share URL Cleaner

A native iOS (SwiftUI) app that strips tracking parameters from URLs you share —
`utm_source`, `fbclid`, `gclid`, and the rest — using AdGuard-syntax `$removeparam` filter
lists. Native port of the Android [ShareURLCleaner](../ShareURLCleaner).

## Use it

1. **App** — open the app and tap **Update Now** to download the rules. Four filter lists
   are enabled by default ([AdGuard URL Tracking][adguard], [Legitimate URL Shortener][lus],
   [uBlock Origin Privacy][ubo], and Kenichi's own list); you can untick any of them or add
   your own URL. **Auto Update Daily** refreshes them in the background. There are no rules
   until that first download, so shared URLs aren't cleaned before it.
2. **Share Extension** — from any app's share sheet (Safari, Notes, …), pick **URL
   Cleaner**. It shows the cleaned URL with **Copy** and **Share…** buttons. (iOS can't
   silently re-share like Android, so you confirm the result.)

Every http(s) URL in the shared text is cleaned, not just the first one.

[adguard]: https://github.com/AdguardTeam/FiltersRegistry
[lus]: https://github.com/DandelionSprout/adfilt
[ubo]: https://github.com/uBlockOrigin/uAssets

## Aggressive mode

Some links are a tracking hop rather than a destination: shorteners (`bit.ly`, `b23.tv`)
and the share wrappers Facebook, Instagram and Threads hand out. Cleaning those does
nothing, because the tracking is in the path, not the query.

**Aggressive Mode** follows such a link to where it actually goes and cleans *that*:

- **Off** (default) — clean the shared link only. Nothing leaves the device.
- **Selected Sites** — follow only the hosts on an editable list (shorteners and share
  wrappers, shipped filled in). Those hosts see one request.
- **All Sites** — follow every shared link. Every site you share sees a request.

The chain is followed to its end — a shortener pointing at a shortener is one share, not
three — with short timeouts, so a slow host degrades to "share the link as-is".

## Privacy

Cleaning happens on-device. The app has no accounts, ads or analytics.

It makes network requests in exactly two cases: downloading the filter lists you enabled,
and — only when you turn Aggressive Mode on — fetching a shared link to find its
destination. With Aggressive Mode off, no shared URL ever leaves the phone.

## Develop

See [CLAUDE.md](CLAUDE.md) for build commands, the App Group setup, the Android↔iOS parity
map, and the logic self-check.

## License

MIT — see [LICENSE](LICENSE). The app icon is based on [Phosphor Icons](https://phosphoricons.com), also MIT.
