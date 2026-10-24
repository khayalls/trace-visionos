# TRACE privacy and local data

TRACE uses ARKit hand joints to draw generic hand models and record movements when the wearer chooses **Record motion**. The models are not scans of the wearer.

## What the app uses

- Hand Tracking permission, requested on entering the immersive studio.
- A world-tracking device pose to establish a stable stage. The app does not store the world map or the device-pose stream.
- Live joint transforms in memory while the studio is active.

The app does not capture video, photographs, camera frames, or audio. It does not request scene reconstruction or plane detection. There is no analytics SDK, advertising SDK, account system, networking client, or cloud-sync implementation in the audited source.

## What a saved study contains

A study can include up to ten seconds of stage-relative joint positions and orientations, left/right hand identity, joint and hand tracking flags, provider state, relative frame timestamps, a creation date, a generated study UUID, a title, and the selected hands. Low-confidence inferred joint transforms keep their confidence flags. Simulator fixtures are labeled synthetic.

Studies are JSON files in the app's private container at `Library/Application Support/TRACE/Takes/`. Writes are atomic. Loading checks the schema and ignores malformed studies. No wearer recordings are bundled with the source repository; the hand-model JSON files contain generic CC0 model geometry.

## Retention and deletion

Studies remain locally until deleted using **Saved studies → Delete study**, or until the app's data is removed. Deletion removes the app's study file; it is not a secure-erasure guarantee and does not remove copies in operating-system backups. TRACE uses normal app-container protections and does not add its own file encryption. Operating-system backup and device-management policies may apply. TRACE itself does not upload studies.

## Development and publication

Keep personal signing settings in ignored `Configuration/LocalSigning.xcconfig`. Keep recordings, signed app bundles, provisioning profiles, device logs, and diagnostic reports out of Git. The repository includes a publication guard and a credential-scanning workflow; these are checks, not a guarantee that arbitrary future files are safe to publish.

Review the staged files and commit identity before every public push. Use a GitHub-provided noreply email if you want to keep your account email private. Repository ownership and the public account name remain visible on GitHub.
