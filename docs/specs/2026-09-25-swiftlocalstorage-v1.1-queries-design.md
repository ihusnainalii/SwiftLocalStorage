# SwiftLocalStorage 1.1 — Query Track Design Spec

**Status:** Approved · **Date:** 2026-09-25 · **Target:** `v1.1.0` · **Branch:** `feat/v1.1-queries`

Builds on the v0.6 indexes spec and the 1.0 API freeze. Everything here is additive: the PR-time
`diagnose-api-breaking-changes` check against `v1.0.0` must pass.

## 1. Goals

1. Live queries over indexed filters, so a SwiftUI list of "unread articles in topic X" doesn't
   refetch and decode the whole type on every write.
2. Two more string-index conditions: prefix and any-of.
3. Cap memory for the two calls that decode a whole type at once (`fetch(_:where:options:)` and
   `migrateAll(_:)`).
4. CI housekeeping: move the GitHub Actions off the deprecated Node 20 runtime. release-please stays.

## 2. Public API

```swift
// Indexed live query: same semantics as updates(of:options:).
for try await unread in storage.updates(
    of: Article.self,
    matching: [.equals("topic", "swift"), .equals("isRead", false)],
    orderedBy: .descending("publishedAt"),
    options: FetchOptions(limit: 50)
) { … }

// New string conditions.
.hasPrefix("email", "ada")                   // string index starts with "ada"
.oneOf("status", ["draft", "review"])        // string index equals any listed value

// Repository equivalent (Entity: LocalStorageIndexed).
articles.updates(matching:orderedBy:options:)
```

```swift
extension LocalStorage {
    public func updates<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        of type: T.Type, matching filters: [StorageFilter], orderedBy order: StorageIndexOrder? = nil,
        options: FetchOptions = .default
    ) -> AsyncThrowingStream<[T], any Error>
}

extension StorageFilter {
    public static func hasPrefix(_ name: String, _ prefix: String) -> Self
    public static func oneOf(_ name: String, _ values: [String]) -> Self
}
```

## 3. Semantics

| Situation | Behaviour |
|---|---|
| `updates(of:matching:…)` | Emits the current results immediately, then one refetch per burst of writes to the type; finishes with the error if a refetch fails; ends when the consumer is cancelled. Re-indexing (declaration change) happens inside the refetch, as for every indexed query. |
| `hasPrefix(name, p)` | Matches records whose value starts with `p` (case- and diacritic-sensitive, like `equals`). `p == ""` matches every record that has a value. |
| `oneOf(name, values)` | Matches records whose value is in `values`. An empty list matches nothing. |
| Several string conditions on one index | ANDed: `equals` and `oneOf` intersect into one value set (an empty intersection matches nothing); a second `hasPrefix` must be compatible (one prefix extends the other) and the longer one wins, otherwise the query matches nothing. |
| Two different `equals` on one index | Today this is a precondition failure ("Contradictory filters"). In 1.1 it matches nothing, consistent with the intersection rule. This relaxes a crash into a valid query, so it isn't a breaking change. |
| Missing value (`nil`) | Never matches any string condition, as today. |
| Number filter on a string index (or vice versa), unknown name | Precondition failure, as today. |
| `fetch(_:where:options:)` | Walks the type in batches of 500 in `options.sort` order, filtering each batch and stopping once `offset + limit` matches are found. Results are identical to 1.0. |
| `migrateAll(_:)` | Walks the type in batches of 500, rewriting outdated records. Stops at the first failure, as today. |

Batched walks run as several store calls, like `all(_:batchSize:)`. A write that lands between
two batches may be seen or missed. `migrateAll` and the insertion-ordered sorts (`oldestFirst`,
`newestFirst`) never see a record twice, because rewrites change neither creation time nor
sequence. With the update-ordered sorts, a record updated mid-walk can move across a batch
boundary and appear twice or not at all. That's documented; callers who need a snapshot use
`fetch(_:)` plus an in-memory filter.

## 4. Architecture

- `IndexQuery` per string slot: `values: [String]?` (equality and any-of, intersected) and
  `prefix: String?`, plus a `matchesNothing` flag for contradictions and empty lists. This
  replaces today's single `strings[slot]`, with `equals` becoming a one-element set.
- SwiftData predicate per string slot:
  `(!hasValues || values.contains(s ?? sentinel)) && (!hasPrefix || (s != nil && (s ?? "").starts(with: prefix)))`,
  where `sentinel` is a string no caller can store (`"\u{0}"`). A contradictory query
  short-circuits to an empty result before reaching the engine.
- The in-memory engine evaluates the same rules in `IndexQuery.matches`.
- `updates(of:matching:…)` reuses the change-hub subscription and coalescing of
  `updates(of:options:)`; only the refetch closure differs (the indexed fetch).
- The two batch walks use `engine.records(…limit: 500, offset: n…)` in a loop.

If the larger `#Predicate` hits type-checker or SwiftData translation limits, the fallback is to
build per-slot sub-predicates and combine them with `Predicate.evaluate`. The API doesn't change
either way.

## 5. Out of scope

OR across different indexes, `NOT`, case-insensitive matching (store a lowercased index
instead), contains/suffix matching, and number any-of.

## 6. Testing

- Both engines: prefix (including empty prefix and nil values), oneOf (including an empty list),
  intersection of `equals`/`oneOf`, compatible and incompatible prefixes, each combined with
  number conditions, order, limit/offset, count and page.
- Indexed live query: an initial emit; emits after relevant and irrelevant writes (still one per
  burst); the result respects filter, order and limit; a declaration change re-indexes; a failing
  store finishes the stream; the repository variant.
- Batched `where:` across a batch boundary (1,200 records) with sort, offset and limit: identical
  to an unbatched reference. Batched `migrateAll` over 1,200 outdated records.
- Coverage stays at or above 90%; the API breakage check against `v1.0.0` passes.
- Benchmarks gain "filter 1,000 by prefix" and "filter 1,000 by oneOf" rows.

## 7. Release

`v1.1.0`, through release-please (it needs "Allow GitHub Actions to create and approve pull
requests" enabled in the repository settings). README, DocC (*Indexed Fields*, *Observing
Changes*), `docs/benchmarks.md` and ROADMAP are updated in the same PRs.
