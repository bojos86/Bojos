# BBK OCR App (Flutter)

- Upload image + Camera scan
- On-device OCR (Arabic + English)
- Extracts & validates: BBK debit (12, start 12/22), IBAN (30 + checksum), SWIFT/BIC (8/11), Amount/Currency, Beneficiary Name/Bank, Purpose (Field 70), Charges (OUR/SHA)

## Build via GitHub Actions
Just push this repo. The included workflow will:
1) `flutter create .` (android only)
2) Restore `pubspec.yaml` and `lib/app_main.dart` → `lib/main.dart`
3) Build release APK and upload as artifact.
