# ShareURLCleaner (iOS)

Native SwiftUI port of the Android `../ShareURLCleaner` app. Strips tracking query
parameters (`utm_*`, `fbclid`, `gclid`, …) from shared URLs using AdGuard's
`$removeparam` filter list.

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
  `d=$(mktemp -d); cp Shared/{FilterRule,UrlCleaner,ShareTextCleaner,FilterParser}.swift "$d"; cp Tests/SelfCheck.swift "$d/main.swift"; (cd "$d" && swiftc *.swift -o check && ./check)`

## Notes

- iOS-only (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). The Xcode template's
  macOS/visionOS support was removed — `BGTaskScheduler` and `UIKit` aren't on macOS.
- App Group capability must be enabled for team `3V7GQVU2ZR`. If signing fails, that's the
  one manual step: Xcode → target → Signing & Capabilities → + App Groups.
- The share extension can't silently re-open the system share sheet (iOS limitation) — it
  shows the cleaned URL with Copy / Re-share buttons instead.
