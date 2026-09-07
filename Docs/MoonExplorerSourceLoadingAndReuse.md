# Explorer source loading and terrain reuse

This follows the physical Release comparison in `MoonExplorerEntryAndImport.md`.
`LandAnywhereMoonPlan.md` controls geometry, provenance and acceptance. Evidence
for this work is in `/tmp/LM-Source-Rebuild-2026-09-06/`.

## Bounded source loading

The first device entry spent 24.042 seconds resolving sources. Independent
source slabs were awaited serially. Region loading now keeps at most four
requests in flight, retaining catalog order when resolving results. Every
request still uses the existing byte-range, size, digest and persistent-store
checks. One unavailable source retains the existing fallback behavior;
cancelling navigation cancels the batch and its outstanding requests.
The standalone resumable Download Region operation is unchanged.

Release visionOS 26.5 Simulator validation passed 19 tests with no failures or
skips in `Sources-Retry.xcresult`. New tests cover bounded concurrent requests,
out-of-order completion, catalog-order results, partial failure, offline cache
reuse, empty input and cancellation without publishing partial products. The
initial Release test build lacked testability; the passing retry explicitly
sets `ENABLE_TESTABILITY=YES`. Source/post/seam tests also pass. No source data,
source ordering or sampling arithmetic changed in this item. A fresh physical
source-load timing remains to be measured; four requests do not imply a
fourfold speedup on every network.
