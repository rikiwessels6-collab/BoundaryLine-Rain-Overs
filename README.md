# BoundaryLine Rain & Overs

SwiftUI iPad rain-delay calculator for CA ODC, WNCL, BBL, WBBL and ICC Men's ODI / T20I.

**Status: unverified. App Store release on HOLD.** A green CI run means the code compiles and the
self-tests pass on a simulator. It does not mean the app has been checked on a device or is ready to release.

- `Sources/BoundaryLineRain/` the app (`BoundaryLineSelfTests.swift` holds the in-app self-tests)
- `Tests/` runs those self-tests under XCTest in CI
- `project.yml` XcodeGen spec; the Xcode project is generated in CI and not committed
- `docs/` audit notes, independent Python expectations, and the as-received v7.4 source
- Playing Conditions PDFs are intentionally not committed
