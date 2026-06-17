# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0/).

## [Unreleased]

### Added
- Added a `golangci-lint` (gocritic/ruleguard) rule and `client-golangci` CI job that bans variable-indexed `tx.Outputs[i]`/`tx.Inputs[i]` access in non-test production code, steering callers to the bounds-checked `OutputAt`/`InputAt` accessors (#36)
- Added native Go fuzz targets across the beacon, network/security handshake, protocol, tBTC, tECDSA (DKG and signing), and bitcoin packages, asserting panic-free unmarshaling/deserialization of arbitrary untrusted input (#36)
- Added a non-blocking `client-race-test` CI job (race detector, scheduled and manual-dispatch only) (#36)
- Added the dev-only `github.com/quasilyte/go-ruleguard/dsl v0.3.23` tooling dependency (pinned via `tools.go`) used by the new lint rule (#36)
- ClusterFuzzLite CI integration: a per-PR fuzzing workflow (`code-change` mode, 300s, address sanitizer) and a scheduled nightly batch fuzzing workflow (`batch` mode, 1800s, daily cron + manual dispatch), backed by `.clusterfuzzlite/` build infra (Dockerfile, `project.yaml`, `build.sh` compiling 42 `Fuzz*` targets, plus a `check_targets.sh` drift guard). The per-PR workflow triggers on changes to `pkg/**`, `.clusterfuzzlite/**`, `go.mod`, `go.sum`, `.dockerignore`, `.github/workflows/cflite_pr.yml`, and `.github/workflows/cflite_batch.yml` (i.e. fuzzed code, fuzz build infra, dependencies, and the workflows themselves) (#37)
- New `target-sync` PR check that runs `.clusterfuzzlite/check_targets.sh` on every qualifying PR and fails the PR when a `Fuzz*` target under `pkg/` is not registered in `build.sh`; an unregistered target would otherwise silently get zero ClusterFuzzLite coverage (#37)
- `rapid` model-based property tests for retry participant selection (F-009): sub-multiset / all-or-nothing operator inclusion, minimum-seat retention, determinism, and operator-exclusion invariants for key generation and signing (#37)
- `rapid` property test for Ethereum redemption event conversion (F-014) asserting `convertRedemptionRequestedEvent` maps `TxMaxFee` from the event's `TxMaxFee` (not `TreasuryFee`) and reproduces all scalar fields (#37)
- `FuzzIdentityUnmarshal` fuzz target asserting the libp2p `identity.Unmarshal` never panics on arbitrary input (#37)
- Bitcoin transaction fuzzing improvements: a serialize/re-parse fixed-point property in `FuzzTransactionDeserialize` plus two pinned seed-corpus entries capturing parser quirks (trailing bytes accepted; witness-encoded zero-input txs colliding with the segwit marker on re-encode) (#37)
- Test-only dependency `pgregory.net/rapid v1.3.0` for property-based tests (#37)
- `.clusterfuzzlite/README.md` documenting the fuzz build setup; `.dockerignore` adjustments so the fuzz build context includes `.clusterfuzzlite/**` and committed protobuf code (`**/gen/pb/*.go`); and a `.gitignore` entry for `rapid` failure artifacts (`testdata/rapid/`) (#37)

### Changed
- Re-landed the Tier 0 (lint rule, race-detector CI job, bounds-checked accessors) and Tier 1 (native fuzz targets) portions of the previously reverted #33 testing/correctness hardening work as a single consolidated changeset, corresponding to the original PRs #29 and #30; the ClusterFuzzLite continuous fuzzing (#31) and rapid property tests (#32) are NOT included in this PR (#36)
- Nightly scheduled `-race` CI job: timeout raised from 30m to 60m, and on scheduled-run failure it now upserts a labeled GitHub issue (`race-detector-failure`); behavior is CI-only and gated to scheduled runs (#37)
- Narrowed the ruleguard lint rule for raw `Outputs[$i]`/`Inputs[$i]` indexing to fire only on `bitcoin.Transaction` / `*bitcoin.Transaction`, reducing false positives on unrelated and generated types (#37)

### Security
- Hardened transaction parsing against out-of-bounds crashes on untrusted/malformed Bitcoin-node responses: the SPV redemption and moved-funds-sweep paths now use bounds-checked `OutputAt` accessors and return a wrapped error instead of panicking when a node-supplied transaction has insufficient outputs (#36)
