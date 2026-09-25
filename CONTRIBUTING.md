# Contributing to SwiftLocalStorage

Thanks for your interest. Please read this before opening an issue or a pull request.

## Asking questions

Issues are for confirmed bugs and accepted feature work. Questions go to
[GitHub Discussions](https://github.com/ihusnainalii/SwiftLocalStorage/discussions).

## Reporting security issues

Do **not** file a public issue. Follow [SECURITY.md](SECURITY.md).

## Reporting bugs

1. Search [existing issues](https://github.com/ihusnainalii/SwiftLocalStorage/issues).
2. Confirm you are on the latest tagged release.
3. Include the SwiftLocalStorage version, the Xcode/Swift version, the OS and its version, what you
   expected, what happened, and a minimal reproduction. A failing test using
   `LocalStorage(configuration: .inMemory)` is ideal.
4. Attach logs captured at `StorageLogLevel.debug` if relevant. They never contain payloads.

## Requesting features

Start a Discussion that describes the problem you're trying to solve. Check
[ROADMAP.md](ROADMAP.md) first. Features that add a dependency are out of scope.

## Submitting pull requests

- **Discuss non-trivial changes first** in Discussions.
- **Branch naming:** `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `test/<topic>`, `chore/<topic>`.
- **Conventional Commits** for every commit and the PR title: `feat(cache): …`, `fix: …`,
  `docs: …`, `test: …`, `ci: …`, `chore(release): x.y.z`.
- **Changelog with every change:** each user-visible commit adds a bullet under
  `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog sections: Added, Changed,
  Deprecated, Removed, Fixed, Security).
- **Tests required** for new behavior and for every bug fix. Don't weaken existing tests.
- **Docs in the same PR:** update `README.md`, the DocC catalog and doc comments for any public API change.
- **No breaking changes in 1.x:** CI rejects a PR that breaks source compatibility with the latest
  release (`swift package diagnose-api-breaking-changes`). Additions must be additive.
- **Disclose AI assistance** in the PR description if you used it.

## Development loop

```bash
swift build --build-tests -Xswiftc -warnings-as-errors   # must be clean
swift test --parallel                                     # all green
swift test --sanitize=thread                              # no data races
bash scripts/coverage.sh                                  # line coverage must stay >= 90%
swift package diagnose-api-breaking-changes v1.0.0       # no API breaks (use the latest tag)
swift run -c release SwiftLocalStorageBenchmarks          # before/after numbers for performance PRs
```

## Code conventions

- Zero external dependencies.
- Swift 6 language mode; everything public is `Sendable`.
- SwiftData stays internal. No SwiftData type appears in the public API.
- Every public failure is a `LocalStorageError`.
- Never log payloads.
- Test doubles live in `Sources/SwiftLocalStorage/Testing/` behind `@_spi(SwiftLocalStorageTesting)`.
- Tests use Swift Testing (`@Suite`, `@Test("…")`, `#expect`) and in-memory stores only.

## Releases

1. On a `chore/release-x.y.z` or feature branch, rename `## [Unreleased]` to
   `## [x.y.z] - YYYY-MM-DD`, add a fresh empty `## [Unreleased]`, update the compare links, and
   bump `version.txt`.
2. Commit as `chore(release): x.y.z` and merge the PR with a merge commit.
3. Tag `main` with `git tag -a vx.y.z -m "SwiftLocalStorage x.y.z"`, push the tag, and publish a
   GitHub Release using that version's changelog section as the notes.

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
