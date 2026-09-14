# The SocialApp Xcode project

`SocialApp.xcodeproj` is **hand-maintained and thin**. It exists to (a) build a
`.app` bundle around the `AppShell` package and (b) host the XCUITest target.
There is no XcodeGen, no `project.yml` and no template.

Repo rule (see root `AGENTS.md`): **a `.xcodeproj` change is a
targets/schemes/build-settings change only**. Source files live in Swift
packages. Never hand-edit `project.pbxproj` to add a code file.

## Layout

```
App/
  SocialApp.xcodeproj/
    project.pbxproj                              targets + build settings only
    xcshareddata/xcschemes/SocialApp.xcscheme    shared: build + test action
  Package.swift                                  the AppShell library
  Sources/AppShell/                              all shell source (app + tests read it)
  App/                                           the app target
    SocialAppApp.swift                           @main, 5 lines
    Info.plist                                   UILaunchScreen, bundle id
  Tests/                                         SocialAppTests (unit-ish)
  UITests/                                       SocialAppUITests (XCUITest)
    Info.plist
  PROJECT.md                                     this file
```

The project declares **one local Swift package reference**, `.` (the `App/`
directory itself), resolved through
`XCLocalSwiftPackageReference`/`XCSwiftPackageProductDependency`. That is why
there is no `Package.resolved` in the project and no network fetch: the app
links the library that lives next to it.

## Targets

| Target | Product | Type | Bundle id | Sources |
|---|---|---|---|---|
| `SocialApp` | `SocialApp.app` | application | `dev.hailey.socialapp` | `App/SocialAppApp.swift` **only** |
| `SocialAppTests` | `SocialAppTests.xctest` | unit-test bundle | `dev.hailey.socialapp.tests` | `Tests/` |
| `SocialAppUITests` | `SocialAppUITests.xctest` | ui-testing bundle | `dev.hailey.socialapp.uitests` | `UITests/` |

All three link the `AppShell` package product. The UI-test target sets
`TEST_TARGET_NAME = SocialApp`; the unit-test target sets `TEST_HOST`/`BUNDLE_LOADER`.

Shared build settings (Debug/Release) live on the project object:
`IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SDKROOT = iphoneos`, `SWIFT_VERSION = 6.0`,
`TARGETED_DEVICE_FAMILY = 1,2`. Per-target settings carry bundle id, `Info.plist`
path and `MARKETING_VERSION`.

### Signing

Nothing here needs a signing identity: CI builds with
`CODE_SIGNING_ALLOWED=NO`. `CODE_SIGN_STYLE = Automatic` is what Xcode's UI
expects for a normal checkout, but the CI invocation overrides it.

## Adding a target or a file

* **A new source file for the app**: it does not belong in this project. Add it
  to the `AppShell` (or feature) package under `Packages/`. The project picks it
  up automatically because it links the local package.
* **A new UI/unit test file**: drop it in `App/UITests/` or `App/Tests/` and add
  one `PBXBuildFile` + one entry in that target's `PBXSourcesBuildPhase`. Test
  sources are the one place the project lists code, since XCUITest bundles cannot
  come from a package (the test product must be built by the project).
* **A new target**: add `PBXNativeTarget`, its `XCConfigurationList` +
  `XCBuildConfiguration`s, its `PBXSourcesBuildPhase`, and a `PBXTargetDependency`
  if it needs to build another target first. Then list it in the project's
  `targets` and in the scheme's `<Testables>` if it is a test target.
* **A new package dependency**: add `.package(...)` to `App/Package.swift`; the
  project needs no change for products it already links, but a new *product* needs
  an `XCSwiftPackageProductDependency` and a `PBXBuildFile` in the target.

## Verifying the project

```bash
cd App
xcodebuild -list -project SocialApp.xcodeproj          # sanity: targets + scheme

xcodebuild build-for-testing \
  -project SocialApp.xcodeproj -scheme SocialApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
  -project SocialApp.xcodeproj -scheme SocialApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO
```

CI runs exactly those two commands (`build-for-testing` then
`test-without-building`) in `.github/workflows/ios-selfhosted.yml` and
`.github/workflows/ios.yml`. Those workflows and `.github/workflows/linux.yml`
are also the way to check a pbxproj edit: there is no Xcode on the Linux
workstation this project is developed from.

Note `-scheme` is quite load-bearing: it is the only way to build the app and
both test bundles in one invocation, and `test-without-building` requires the
`-derivedDataPath` used for `build-for-testing`.

## Screenshots / the debug toolbar button

Each tab's toolbar has a debug button (`app.debug.tokenGallery`) that pushes the
DesignSystem `TokenGallery`. That keeps the AC.7 screenshot surface reachable
before there is a Settings screen. CI drives `-uiTestInitialTab N` (see
`ShellLaunchArgument`) to select a tab at launch, then captures the simulator
with `xcrun simctl io <udid> screenshot`.
