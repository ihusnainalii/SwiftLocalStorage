# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.x | ✅ |
| < 1.0 | ❌ |

Fixes land in the latest 1.x minor release.

## Security posture

- **No encryption at rest.** Records are stored in the app's SwiftData store and protected only by
  the platform's data protection. **Do not store secrets** such as tokens, passwords or keys. Use
  the Keychain.
- **No payloads in logs.** Log lines contain operation names, record keys, byte counts and error
  *types*, never payload contents or error descriptions. Record keys include entity IDs and
  key-value keys, so don't use sensitive values as IDs or keys if you enable logging.
- **No network access and no dependencies.** The package makes no network calls and pulls in no
  third-party code.
- **Decoding is defensive.** Corrupt or incompatible records surface as
  `LocalStorageError.decodingFailed`. They never crash the process.

## Reporting a vulnerability

Please **do not** open a public issue.

Use GitHub's
[private vulnerability reporting](https://github.com/ihusnainalii/SwiftLocalStorage/security/advisories/new)
and include a description, the affected versions, and reproduction steps. You'll get an
acknowledgement within a few days and a fix timeline once the report is confirmed.
