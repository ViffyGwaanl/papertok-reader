# Autoresearch: PaperTok engineering health audit

## Metrics
- **Primary**: blocking_findings (unitless, lower is better)

## How to Run
`autoresearch.sh` — should emit `METRIC name=number` lines for blocking_findings.

## What's Been Tried
- #1 baseline keep 0 98b6fb2 — Restore targeted health checks: AI provider center smoke test no longer hardcodes stale zh title, add bgimgFit invalid-value fallback test, add ReadingInfo legacy migration test
- #2 keep 0 d12dd1b — Remove hard analyze blockers by excluding vendored langchain_openai tests from app analyzer gate; current analyze now runs cleanly enough for release gating with warnings only

## Plugin Checkpoint
- Last updated: 2026-03-29T16:04:52.178Z
- Runs tracked: 2 current / 2 total
- Baseline: 0
- Best kept: n/a
- Confidence: n/a
- Canonical branch: fix/audit-health-2026-03-24
- Last logged run: #2 keep d12dd1b — Remove hard analyze blockers by excluding vendored langchain_openai tests from app analyzer gate; current analyze now runs cleanly enough for release gating with warnings only

Z
- Runs tracked: 1 current / 1 total
- Baseline: 0
- Best kept: n/a
- Confidence: n/a
- Canonical branch: fix/audit-health-2026-03-24
- Last logged run: #1 keep 98b6fb2 — Restore targeted health checks: AI provider center smoke test no longer hardcodes stale zh title, add bgimgFit invalid-value fallback test, add ReadingInfo legacy migration test
- Pending run awaiting log_experiment: flutter analyze --no-fatal-infos --no-fatal-warnings (n/a)

Z
- Runs tracked: 1 current / 1 total
- Baseline: 0
- Best kept: n/a
- Confidence: n/a
- Canonical branch: fix/audit-health-2026-03-24
- Last logged run: #1 keep 98b6fb2 — Restore targeted health checks: AI provider center smoke test no longer hardcodes stale zh title, add bgimgFit invalid-value fallback test, add ReadingInfo legacy migration test

Z
- Runs tracked: 0 current / 0 total
- Baseline: n/a
- Best kept: n/a
- Confidence: n/a
- Canonical branch: fix/audit-health-2026-03-24
- Pending run awaiting log_experiment: flutter test test/ai_provider_center_smoke_test.dart test/config/shared_preference_bgimg_fit_test.dart test/config/shared_preference_reading_info_migration_test.dart -r compact (n/a)

Z
- Runs tracked: 0 current / 0 total
- Baseline: n/a
- Best kept: n/a
- Confidence: n/a
- Canonical branch: fix/audit-health-2026-03-24
