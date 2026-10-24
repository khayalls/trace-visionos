# Public-repository privacy audit

Audit date: **2026-10-24**. Scope: the complete TRACE source distribution, build configuration, tests, documentation, images, bundled hand assets, prepared local Git history, and all advertised branches/tags of the linked GitHub repository.

## Result

The cleaned source is prepared for public review. No API keys, passwords, access tokens, or private keys were detected by the credential scans or manual data-flow review. Confirmed personal information in the original local delivery has been removed from the public source and source archive. The linked remote repository has not been modified by this audit.

One privacy item remains on GitHub: the existing initial commit exposes the original personal author display name. Its email uses GitHub noreply. The public repository currently contains only its initial README, not the app source or the private local delivery artifacts.

## Findings and remediation

| Finding | Location/category | Disposition |
| --- | --- | --- |
| Signed executable and provisioning profile contained development identity and registered-device metadata | Original local `Builds/` directory | Excluded from source, Git, and source archive; preserved privately outside the source tree |
| Development team, personal bundle identifiers, and personal setup instructions | Xcode project, README, verification notes | Replaced with generic defaults and neutral documentation |
| User-directory paths, signing certificate information, device identifiers, and process details | Original build/device logs | Raw logs excluded; public verification uses aggregate results |
| Personal machine/session details in delivery notes | README and verification JSON | Rewritten as reusable project documentation |
| Nonessential PNG EXIF chunks | Eight screenshots/icon layers | Removed; compressed image pixel payloads verified unchanged |
| Personal author display name | Existing remote initial commit | Outstanding remote-history item; a clean local root commit uses the public account alias and noreply email |
| API credentials/private keys | Source, assets, and advertised remote history | None detected; no credential revocation was indicated by the scan findings |

The ignored local signing file is intentionally retained for development convenience. It is not tracked or included in the source archive. Do not share a ZIP made from the entire development folder.

Third-party hand-asset author credit and upstream provenance remain intact. These identify the asset creator and are not the app developer's personal information.

## Code and data-flow review

All 15 Swift files were unchanged by this cleanup. Review covered the app entry point, UI, recording/playback state, ARKit lifecycle, geometry loading/deformation, local storage, synthetic samples, and tests. The offline asset-conversion utility and new publication tooling were also reviewed.

- No runtime networking client, backend endpoint, analytics SDK, account credential, remote configuration, or third-party runtime package was found.
- ARKit Hand Tracking is requested explicitly. World tracking supplies a stable stage reference. No camera-frame, microphone, scene-reconstruction, or plane-detection implementation was found.
- Motion JSON is written atomically inside the app container. Saved studies include joint transforms, tracking confidence, timestamps, a creation date, and generated study metadata. See [PRIVACY.md](../PRIVACY.md).
- No wearer recordings, private screenshots, certificates, provisioning profiles, raw logs, or compiled executables are included in the public file set. Bundled JSON hand assets contain generic model geometry; fixtures are synthetic.
- App-container protections and operating-system backups apply; the app does not add custom encryption or secure erasure. This is documented without claiming that movement data is anonymous.

## Verification

- Gitleaks **8.30.1**, official release binary verified by SHA-256: no credential findings in the original local delivery, cleaned source snapshot, existing advertised remote history, or prepared publication history.
- Publication guard: checks the exact staged bytes, tracked files, historical blobs, commit author/committer email privacy, prohibited private file categories, personal paths, signing literals, credential patterns, private network addresses, and PNG metadata.
- Owner-specific residual check: no original owner-directory name, original personal author name, original team identifier, personal bundle identifier, hardware identifier pattern, or private email was found in the publication file set. The private comparison values are not embedded in public tooling.
- Guard self-tests: eleven synthetic detection cases, two safe fixtures, a partially staged secret hidden by a harmless worktree edit, a removed historical private path, and a private historical email were all handled as expected. Matched values are not echoed.
- Eight PNGs: metadata stripped, compressed pixel payloads unchanged. Simulator previews contain synthetic hands and generic simulator scenery.
- Core regression: **25 tests passed**. Simulator build: **passed**. Exported public-source UI regression: see [Verification.json](Verification.json) for the final result.
- `SourceSHA256.json` records the publication files except the checksum manifest itself. The source ZIP is generated from the audited Git commit, excluding ignored private settings and `.git` metadata.

The GitHub Actions workflow is supplied as an inactive template at `Tools/privacy-workflow.yml`. The saved Git connection lacks workflow-write permission, and the connected integration could not update the branch. Active workflow publication was rejected; the source can be published without activating a workflow. Automated GitHub checks are therefore not enabled. The template uses a commit-pinned checkout, checksum-pinned scanner, read-only repository permissions, and no embedded credentials. Local privacy and credential scans pass. The local pre-commit hook is enabled in the prepared checkout; future clones must enable it using the README command.

## Remote state and remaining decision

At audit time, `main` points to initial commit `6408d3eaeb94284c9cc8991e078a66ff7fbb5b75`. The only advertised branch is `main`; no tags were advertised. Its single tracked file is the project README. Credential scanning found no secrets in that history, but the original author display name remains visible in commit metadata.

The prepared local repository starts with a clean root commit using the public account alias and the account's GitHub noreply email. It has not merged the original commit as a parent. The repository owner explicitly approved replacing the initial history and publishing the cleaned source. The original remote state was cloned privately for recovery. Publication verification follows the branch update.

Replacing branch history cannot erase copies already cloned or all cached commit views. GitHub explains these limits in its [sensitive-data removal guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository). GitHub also documents [commit email privacy](https://docs.github.com/en/account-and-profile/concepts/email-addresses).

## Limits

This audit assesses publication privacy and credential exposure in the reviewed snapshot. Pattern scanners cannot prove that arbitrary future files contain no sensitive data. It is not a penetration test or a certification of hand-tracking accuracy, headset performance, or production readiness. Public GitHub ownership, the account alias, and upstream asset credit remain visible by design.
