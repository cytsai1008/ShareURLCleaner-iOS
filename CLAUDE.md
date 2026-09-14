# ShareURLCleaner (iOS)

Native SwiftUI port of the Android `../ShareURLCleaner` app. Strips tracking query
parameters (`utm_*`, `fbclid`, `gclid`, …) from shared URLs using AdGuard-syntax
`$removeparam` filter lists. Feature parity with the Android app is the goal — when the
two disagree, the Android source is the reference.

## Targets / layout

- `Shared/` — pure logic + storage. **Compiled into both targets** (listed in each
  target's `fileSystemSynchronizedGroups`). No UIKit/SwiftUI deps; keep it that way so the
  standalone self-check keeps compiling.
- `urlclean/` — the app (settings screen, background refresh). App target only.
- `ShareExtension/` — the share-sheet extension (clean → Copy / Re-share). Extension target only.

App and extension share data through the App Group **`group.com.cytsai.urlclean`**:
`filter_rules.txt` (rules) + `UserDefaults` (settings) live in the group container.

## Build & test

- Build: `xcodebuild -project urlclean.xcodeproj -scheme urlclean -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  (xcodebuild needs to run outside the sandbox — DerivedData + CoreSimulator). The Xcode MCP
  `BuildProject` also works.
- Logic self-check (no Xcode needed):
  `d=$(mktemp -d); cp Shared/{FilterRule,UrlCleaner,ShareTextCleaner,FilterParser,RedirectResolver}.swift "$d"; cp Tests/SelfCheck.swift "$d/main.swift"; (cd "$d" && swiftc *.swift -o check && ./check)`

## Parity map (Android → iOS)

| Android | iOS |
|---|---|
| `core/UrlCleaner.kt` | `Shared/UrlCleaner.swift` |
| `core/ShareTextCleaner.kt` | `Shared/ShareTextCleaner.swift` |
| `core/RedirectResolver.kt` | `Shared/RedirectResolver.swift` |
| `data/FilterRepository.kt` (parse) | `Shared/FilterParser.swift` |
| `data/FilterRepository.kt` (I/O) | `Shared/FilterStore.swift` + `urlclean/FilterDownloader.swift` |
| `data/SettingsDataStore.kt` | `Shared/Settings.swift` |
| `MainActivity.kt` | `urlclean/SettingsView.swift` |
| `ShareActivity.kt` | `ShareExtension/ShareViewController.swift` |
| `worker/FilterUpdateWorker.kt` | `urlclean/BackgroundRefresh.swift` |

Not ported: localized strings (Android ships `zh-Hant` / `zh-Hans`; iOS is English-only) and
the "Aggressive Mode" second share target (Android uses a manifest activity-alias; iOS share
extensions have no equivalent, so the setting is the only way in).

## Notes

- iOS-only (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). The Xcode template's
  macOS/visionOS support was removed — `BGTaskScheduler` and `UIKit` aren't on macOS.
- App Group capability must be enabled on both targets. If signing fails, that's the
  one manual step: Xcode → target → Signing & Capabilities → + App Groups.
- The share extension can't silently re-open the system share sheet (iOS limitation) — it
  shows the cleaned URL with Copy / Re-share buttons instead.
- Aggressive mode (follow redirects before cleaning) makes a network call in the share path.
  `RedirectResolver` keeps 3s/5s timeouts and a pinned `curl/8.7.1` User-Agent on purpose —
  read the doc comments before changing either.
