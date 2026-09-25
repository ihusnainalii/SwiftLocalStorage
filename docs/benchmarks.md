# Benchmarks

Wall-clock timings of the core operations against a real on-disk SwiftData store. Each figure is
the median of 5 runs.

```bash
swift run -c release SwiftLocalStorageBenchmarks
```

The target uses only the public API. It opens a store named `SwiftLocalStorageBenchmarks` and
empties it before and after the run. Numbers depend heavily on the device and disk, so compare
runs on the same machine rather than treating these as absolutes.

## Results (1.1.0)

Apple M1 Pro, macOS 27.0, Swift 6.4, release build.

| Operation | Median of 5 |
|---|---:|
| save 1 (one batch) | 0.91 ms |
| fetch all of 1 | 0.37 ms |
| deleteAll of 1 | 0.50 ms |
| save 100 (one batch) | 16.10 ms |
| fetch all of 100 | 3.52 ms |
| deleteAll of 100 | 0.88 ms |
| save 1000 (one batch) | 147.36 ms |
| fetch all of 1000 | 33.00 ms |
| deleteAll of 1000 | 2.82 ms |
| save 1 MB payload | 5.95 ms |
| fetch(id:) 1 MB payload | 1.83 ms |
| save 10 MB payload | 59.74 ms |
| fetch(id:) 10 MB payload | 19.51 ms |
| filter 1,000 by index (matching:) | 4.02 ms |
| filter 1,000 by prefix (hasPrefix) | 4.21 ms |
| filter 1,000 by any-of (oneOf) | 3.93 ms |
| filter 1,000 by closure (where:) | 36.87 ms |

## Reading the numbers

- **Batch saves scale linearly** at roughly 0.15 ms per record. 1.0 fixed a quadratic key lookup
  that made a 1,000-record batch take about 1.5 s.
- **`fetch` cost is mostly decoding**, about 0.03 ms per small record. Use `limit`, `page` or
  `all(_:batchSize:)` for large types.
- **An index filter is about 9× faster than a closure filter** on 1,000 records, because only the
  matching rows are decoded. The gap grows with the number of records. Prefix and any-of filters
  cost the same as equality.
- **Closure filters walk in batches of 500** since 1.1, which keeps memory bounded on large types.
  That costs about 10% on this run (37 ms against 33 ms in 1.0), and a filter with a `limit`
  stops as soon as it has enough matches.
- **Large payloads cost about 5.5 ms per MB to save and 1.8 ms per MB to read.** Keep images and
  files on disk and store their paths.
- **`deleteAll` is a single statement**, so it stays cheap at any size.
