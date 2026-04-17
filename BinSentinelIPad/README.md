# Bin Sentinel iOS Frontend (SwiftUI)

This folder holds the native iOS app (iPhone and iPad).
The Xcode project is `BinSentinelIPad/BinSentinelIPad.xcodeproj`.
The app reuses the existing backend API contract:

- `POST /scan` (multipart form: `image`, `city`)
- `GET /history`

## What is included

- SwiftUI app entry point
- Camera preview + photo capture (AVFoundation)
- API client for `/scan` and `/history`
- Result card and last-scan summary from `/history`
- City selector matching existing web cities (`seattle`, `nyc`, `la`, `chicago`)

## Open and run the Xcode project

1. Open `BinSentinelIPad/BinSentinelIPad.xcodeproj` in Xcode.
2. In Signing & Capabilities, ensure camera permissions are configured.
3. Add this to `Info.plist`:
   - `Privacy - Camera Usage Description` = `"Bin Sentinel needs camera access to scan items for classification."`
4. Set backend URL in `BinSentinelIPad/BinSentinelIPad/Config/AppConfig.swift`.

## Local backend testing

If testing on a physical iPhone or iPad against a local backend:

- Run FastAPI on your Mac network IP (not localhost from iPad's perspective).
- Example base URL: `http://192.168.1.15:8000`

## Notes

- Phase 1 implemented: manual capture -> upload -> verdict.
- Phase 2 implemented: result auto-dismiss, improved error banner UX, and readable history timestamps with loading state.
- Phase 3 implemented: optional auto-scan mode using motion/stability gating and a post-scan cooldown.
