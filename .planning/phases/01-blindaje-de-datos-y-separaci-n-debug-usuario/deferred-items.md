# Deferred Items — Phase 01

Out-of-scope discoveries found during execution, not fixed (per scope boundary rule).

## From 01-01 (Task 2 verification)

- `lib/presentation/widgets/trigger_map.dart:208` — `flutter analyze` reports dead code
  + a dead-null-aware-expression warning. File is not in 01-01's `files_modified` list and
  was already modified before this plan ran (likely touched by a parallel/earlier plan).
  Not fixed here — out of scope for DATA-01/DATA-02.
- `lib/presentation/pages/data_browser_page.dart:232` — `WillPopScope` deprecated
  (info-level, pre-existing before this plan's edits, unrelated to the destructive-action
  removal this plan performs). Not fixed — no acceptance criterion in 01-01 requires it.
