# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0/).

## [Unreleased]

### Added
- `security/` directory with white-box pentest deliverables: architecture, attack surface, critical paths, crypto review, threat model, and smart-contracts analysis, plus 17 verified findings (F-01 through F-17) each with a code reference and status (#2)
- `SECURITY-BREAKING-CHANGES.md` documenting the F-02/F-03 wire-breaking changes and the required coordinated-upgrade path (#2)
- Domain-separation info labels for ECDH key derivation: `gjkrEcdhInfo`, `dkgEcdhInfo` (`tecdsa-dkg`), and `signingEcdhInfo` (`tecdsa-sign`), plus a compile-time assertion that `MemberIndex` is 1 byte (#2)
- Tests for ECDH domain separation, `G1HashToPoint` determinism/wire-format, deduplicator concurrency, and Solidity reentrancy + storage layout (#2)

### Changed
- `ephemeral.PrivateKey.Ecdh` now takes an `info []byte` parameter and derives the symmetric key with HKDF-SHA256 instead of SHA-256; this changes the exported signature (compile break for external callers) and the derived session key (wire-incompatible with older nodes) (#2)
- `altbn128.G1HashToPoint` reimplemented from try-and-increment to a bounded counter-based `SHA-256(m || ctr)` (max 64 attempts); it produces a different G1 point for the same input (consensus-incompatible) and now panics if no valid point is found within the bound (#2)
- `RandomBeacon` relay-entry gas offset `_relayEntrySubmissionGasOffset` raised from 11250 to 13450 to account for the reentrancy-guard SSTOREs (mirrored in the test fixture) (#2)
- Enabled `storageLayout` output selection in the random-beacon Hardhat config, removed `scryptsy` from `yarn.lock`, and added `.envrc*`, `strix_runs/`, and `.claude/` to `.gitignore` (#2)

### Fixed
- `tbtc` deduplicator notify methods (`notifyDKGStarted`, `notifyDKGResultSubmitted`, `notifyWalletClosed`) now use a single atomic `cache.Add` instead of non-atomic check-then-act, fixing a TOCTOU race (#2)

### Security
- Added an inline reentrancy guard (`nonReentrant` modifier, `_reentrancyStatus` storage slot, `ReentrantCall` error) to both `RandomBeacon.submitRelayEntry` entrypoints (#2)
