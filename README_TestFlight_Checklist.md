## TestFlight and App Store Upload Checklist (OpenAPS)

This checklist is tailored to current settings:
- Team: T2LQ8V9YPW
- Bundle ID: ru.zamot.freeeapsx
- App Group: group.ru.zamot.freeeapsx
- Display Name: OpenAPS
- Marketing Version / Build: 1.0.1 (2)

### 1) Versioning
- [x] ConfigOverride.xcconfig: `APP_VERSION = 1.0.1`, `APP_BUILD_NUMBER = 2`
- [x] Ensure Info.plist uses `$(MARKETING_VERSION)` and `$(BUILD_VERSION)`

### 2) Signing & Identifiers (App Store Connect and Developer Portal)
- [ ] In Apple Developer → Identifiers → App IDs: confirm `ru.zamot.freeeapsx` exists.
- [ ] Capabilities match entitlements:
  - HealthKit (read/write)
  - NFC Tag Reading
  - App Groups: `group.ru.zamot.freeeapsx`
- [ ] Create App Group `group.ru.zamot.freeeapsx` and add to the app ID.
- [ ] Ensure provisioning profiles (iOS App + Watch, if needed) include these caps.

### 3) App Store Connect App Record
- [ ] Create new app with unique name: OpenAPS (or choose unique name variant)
- [ ] Bundle ID: ru.zamot.freeeapsx
- [ ] SKU: any unique string
- [ ] Primary language and category

### 4) Privacy
- [ ] App Privacy: Data types collected and usage (Health data, Bluetooth, NFC)
- [ ] Encryption: `ITSAppUsesNonExemptEncryption = false` unless you use custom crypto.
- [ ] NSPrivacyManifest if required by frameworks (Xcode may auto-generate). Verify during archive validation.

### 5) Assets & Metadata
- [x] App icon complete (1024 marketing icon present in asset catalog)
- [ ] Screenshots for iPhone and Apple Watch (if watch app included)
- [ ] Description, keywords, support URL, marketing URL

### 6) Build Preparation
- [ ] Scheme set to Release for archive
- [ ] Increment build number for each upload
- [ ] Clean build folder

### 7) Archive and Upload (Xcode)
1. Open workspace in Xcode.
2. Product → Scheme → OpenAPS
3. Product → Archive (Generic iOS Device or Any iOS Device (arm64))
4. Organizer → Distribute App → App Store Connect → Upload
5. Wait for processing in App Store Connect (10–30 min)

CLI alternative:
```
xcodebuild -workspace FreeAPS.xcworkspace -scheme "OpenAPS" -configuration Release -destination 'generic/platform=iOS' clean archive -archivePath build/OpenAPS.xcarchive
xcodebuild -exportArchive -archivePath build/OpenAPS.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/ipa
``` 
Use Transporter or Xcode Organizer to upload the .ipa.

### 8) TestFlight Setup
- [ ] Add internal testers
- [ ] Enable “Automatic signing” for TestFlight symbols
- [ ] Add compliance answers (encryption)
- [ ] Submit for Beta App Review if required

### 9) Common Gotchas
- HealthKit requires proper usage strings and capabilities
- NFC requires real device tests; provide NFC usage description
- App Groups must match exactly in provisioning and entitlements
- Watch target signing must be consistent if distributing watch app

### 10) Next Steps
- After processing, add testers and release to TestFlight.
- For App Store, fill in all metadata, ratings, and submit for review.


