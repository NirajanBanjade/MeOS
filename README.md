# MeOS

MeOS is a fully offline iPadOS educational adventure about request queues, concurrency, databases, scaling, and system diagnosis. The app uses Swift 6, SwiftUI, SpriteKit, and Foundation only; it has no runtime package or network dependency.

## Build and test

Open `MeOS.xcodeproj` in Xcode 27 or later and select an iPad simulator. The shared `MeOS` scheme includes the unit, integration, performance, and UI test targets.

For command-line verification with Xcode selected:

```sh
xcodebuild -project MeOS.xcodeproj -scheme MeOS -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
xcodebuild -project MeOS.xcodeproj -scheme MeOS -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/MeOS.xcarchive CODE_SIGNING_ALLOWED=NO archive
```

All mission definitions and learning content are compiled into the app. Release credits are shown in-app and packaged as `Credits.txt`; visual assets are in `Assets.xcassets`.
