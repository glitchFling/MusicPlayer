# MusicPlayer Build Architecture

## Overview
MusicPlayer is a SwiftUI iOS app. The "libs" (DeBlytes, FocusOnMe, BetterMusic,
Suitcase, VirtualList) are compiled as **separate dynamic frameworks** embedded
in the app bundle, rather than inlined into the app target.

## Framework Layout
Each lib lives in its own Swift package under `Frameworks/`:

```
Frameworks/
  Core/          Song.swift, SongLibrary.swift        (shared types)
  DeBlytes/      DeBlytes.swift                        → depends on Core
  FocusOnMe/     FocusOnMe.swift                       → no deps
  BetterMusic/   BetterMusic.swift                     → no deps
  Suitcase/      SuitcaseService.swift                 → no deps
  VirtualList/   VirtualListStore.swift                → depends on Core
```

- **Core** holds `Song` and `SongLibrary` because frameworks cannot depend on
  the app target, and both DeBlytes and VirtualList reference `Song`.
- All framework types are `public` so the app can import them.
- The app target imports the frameworks via `import Core`, `import DeBlytes`,
  etc.

## CI Build (`.github/workflows/ios-build-ipa.yml`)
The workflow synthesizes an Xcode project from raw Swift files. Steps:

1. **Collect Swift sources** — copies app `.swift` files + assets into `MusicPlayerSrc/`.
2. **Build lib frameworks** — runs `xcodebuild` on each `Frameworks/<lib>/Package.swift`
   (Release, `generic/platform=iOS`), producing `.framework` bundles in
   `DerivedData/Build/Products/Release-iphoneos/`.
3. **Create Info.plist** — writes the app's `Info.plist`.
4. **Create Xcode project** — hand-crafts `project.pbxproj` with:
   - A `PBXFrameworksBuildPhase` linking all 6 frameworks.
   - A `PBXCopyFilesBuildPhase` ("Embed Frameworks", `dstSubfolderSpec = 10`)
     copying them into `MusicPlayer.app/Frameworks`.
   - `FRAMEWORK_SEARCH_PATHS = ("$(inherited)", "$(BUILT_PRODUCTS_DIR)")`.
   - `LD_RUNPATH_SEARCH_PATHS` including `@executable_path/Frameworks`.
5. **Build for iOS device** — `xcodebuild -configuration Release` (no `clean`,
   which would wipe the frameworks from the shared DerivedData).
6. **Package unsigned IPA** — zips `Payload/MusicPlayer.app`.
7. **Upload artifact** / **publish release**.

## Notes
- iOS does not allow runtime `dlopen` of unsigned dylibs, so these are embedded
  dynamic frameworks loaded at launch — the closest supported equivalent.
- The app build must use `Release` to match the `Release-iphoneos` frameworks.
