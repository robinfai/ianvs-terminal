# iOS App Store release checklist

## Product and policy

- [x] Users can create a one-time SSH connection without an Ianvs account or a remote data service; the connection is not saved.
- [x] App Store icon uses the Ianvs Terminal brand asset and contains no transparency.
- [x] App Store listing draft and privacy policy are present under `docs/app-store/`.
- [ ] Review all listing claims against the final archive.
- [ ] Confirm the publisher does not operate a default backend or collect analytics. If that changes, update the privacy label and policy.
- [ ] Complete the App Store age-rating questionnaire.
- [ ] Complete export-compliance questions for the SSH and cryptography implementation. Do not set `ITSAppUsesNonExemptEncryption` to `false` without a documented compliance determination.

## Apple account and identifiers

- [ ] Confirm the App Store Connect legal entity, paid-app agreements, tax, and banking status as applicable.
- [ ] Register or confirm the production bundle identifier `dev.ianvs.terminal` in Apple Developer. Local profile-signed installs use the team-owned `dev.ianvs.terminal.dev` identifier while retaining the shared `dev.ianvs.terminal` Keychain access group.
- [x] Set Apple Developer Team `ZTF4Y7VNJ2` in the Runner target.
- [ ] Enable automatic signing or install matching distribution credentials after the latest Apple Developer Program License Agreement is accepted.
- [ ] Create the App Store Connect app record with platform iOS, name `Ianvs Terminal`, the final bundle ID, and a stable SKU.

## Build and validation

- [ ] Build with Xcode 26 or newer and the iOS 26 SDK.
- [ ] Run Flutter analysis and focused startup tests.
- [ ] Build the iOS release target without code signing.
- [ ] Archive the final signed build and validate it in Xcode Organizer.
- [ ] Inspect the generated privacy report and resolve every required-reason API declaration before upload.
- [ ] Test a clean install on current iPhone and iPad devices or simulators.
- [ ] Verify the no-data-service one-time SSH path, saved SSH connection, rotation, background/foreground transitions, text input, copy/paste, and data deletion.

## App Store assets and submission

- [ ] Capture screenshots from the release build using fictional data: iPhone 6.9-inch and iPad 13-inch sets at minimum, plus any other required device sets shown by App Store Connect.
- [ ] Fill the Simplified Chinese listing using `IOS_LISTING.zh-CN.md` and add other locales if desired.
- [ ] Provide the public privacy-policy URL and support URL.
- [ ] Complete App Privacy, content-rights, age-rating, advertising-identifier, and export-compliance sections.
- [ ] Upload the archive, wait for processing, and select the build for version 1.0.0.
- [ ] Add review notes explaining the no-account, no-data-service one-time SSH path.
- [ ] Test the processed build in TestFlight before submitting for review.
- [ ] Submit only after all App Store Connect warnings are cleared.
