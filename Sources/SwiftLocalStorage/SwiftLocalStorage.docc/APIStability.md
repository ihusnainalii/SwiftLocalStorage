# API Stability

What 1.x promises, and what it doesn't.

## The promise

From 1.0.0, SwiftLocalStorage follows [Semantic Versioning](https://semver.org). Code that compiles
against 1.x keeps compiling against every later 1.x, and a store written by 1.x opens in every later
1.x. Breaking changes wait for 2.0.

Continuous integration checks every pull request with
`swift package diagnose-api-breaking-changes` against the latest release.

## What may change in a minor release

- New public types, methods and parameters with defaults.
- New cases in the error enums ``LocalStorageError``, ``LocalStorageError/Code`` and
  ``StorageMigrationError``. Handle errors with a `default` branch rather than listing every case.
  Every other public enum is frozen for 1.x.
- Higher minimum platform or Swift tools versions (never in a patch release).
- New internal store schema versions; the migration from older stores stays automatic.

## Not covered

- Declarations behind `@_spi(SwiftLocalStorageTesting)`.
- The storage engine protocol, which stays internal in 1.x.
- Exact log text and the layout of the SwiftData store file.
