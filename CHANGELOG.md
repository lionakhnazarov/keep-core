# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0/).

## [Unreleased]

### Changed
- **BREAKING (wire):** Changed DKG session-ID format to `dkg-<seedHex>-<attempt:016x>` (typed prefix and fixed-width attempt number) and signing session-ID format to `signing-<messageHex>-<startBlock:016x>-<attempt:016x>`. The fixed-width formats guarantee every session ID clears tss-lib's 16-byte minimum-length floor, but are incompatible with the pre-hardening `<x>-<y>` form, so un-upgraded peers compute mismatched session IDs (#8)
- **BREAKING (behavioral):** Made the signing session ID depend on the attempt start block (`announcementEndBlock`) in addition to message digest and attempt number, introducing a new cross-node agreement requirement: even same-version peers that disagree on the attempt start block compute different session IDs and fail to interoperate (#8)
- Computed the session ID once per attempt and threaded it through attempt parameters so the announcer and the protocol cannot drift apart on the GG20 session binding (#8)
- `signing.NewLocalParty(...)` is now called with an additional `fullBytesLen` argument (`(Curve.Params().N.BitLen()+7)/8`). In the hardened tss-lib this parameter is variadic, so existing 5-argument callers still compile; omitting it, however, changes signing message byte-width / leading-zero handling, so this is a behavioral (not compile-breaking) change (#8)
- Added `pull-requests: read` (and job-level `contents: read`) permissions to path-filter jobs in CI workflows so PR change detection runs under `GITHUB_TOKEN` (#8)
- Added tests covering the new session-ID formats, the minimum entropy width, and the session-nonce derivation (`SHA512_256` of the session ID) for DKG and signing (#8)

### Security
- **BREAKING (protocol fork):** Bound tECDSA DKG and signing session IDs into the TSS layer via `SetSessionNonceBytes`, deriving a fail-closed, session-specific GG20 proof nonce (`SHA512_256` of the session ID) for every ceremony. Combined with the changed session-ID formats and the hardened tss-lib pin, mixed-version peers in the same DKG or signing ceremony now derive different session IDs and fail proof verification. Upgrade the whole network at once; do not roll out partially (#8)
- **BREAKING (runtime contract):** `signing.Execute` and the tECDSA DKG `Execute` now thread the caller-supplied session ID into tss-lib's fail-closed minimum-length check. The hardened tss-lib (`tss/params.go`) panics if a session ID is shorter than 16 bytes; keep-core's own callers clear this via the new fixed-width formats, but an external Go caller passing a short or custom session ID will now panic at runtime even though the exported function signatures are unchanged (#8)
- Pinned the `threshold-network/tss-lib` replacement to commit `ae7075f3409e`, integrating the upstream hardening branch (threshold-network/tss-lib#2): GG20 proof transcript tagging/session binding, fail-closed positive `SessionNonce` enforcement, a 16-byte `SetSessionNonceBytes` minimum-length floor, ECDSA/EdDSA `fullBytesLen` signing validation, MtA/range/Paillier proof hardening, and non-canonical EC point rejection (#8)
- Lengthened signing session IDs to include a typed prefix and the attempt start block so repeated same-digest ceremonies no longer reuse the GG20 proof context (#8)
