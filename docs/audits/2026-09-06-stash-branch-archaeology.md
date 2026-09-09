# Stash propagation and branch archaeology: rhea-project

This documentation-only record routes archival evidence to its relevant repository. Snapshot: **2026-09-06, Europe/Moscow**, before the documentation branches created by this pass. Every comparison below uses fixed commit IDs.

The canonical archive is [rhea-project/stash](https://github.com/timelabs-npo/rhea-project/blob/3316bae0770744238099c25ae34e76e7ad4af8b4/stash/README.md). It is a normal Git branch named `stash`, separate from local `refs/stash`. Its 37 archive files total **361,824 bytes**; this pass reconstructed their UTF-8 bytes locally, verified each Git blob SHA-1 and size, and verified SHA-256 after disk readback. The four content-addressed original reports also match the SHA-256 encoded in their paths and total **115,053 bytes**.

The [original collection manifest](https://github.com/timelabs-npo/rhea-project/blob/3316bae0770744238099c25ae34e76e7ad4af8b4/stash/runs/2026-09-06-cloud-001/manifest.json) still records **41 pending items/groups** and `PARTIAL_WD_UNAVAILABLE`. That is the original cloud capture's state, not a statement that this Windows host lacks filesystem access. Mirroring the published archive does not collect the binaries, source trees, VM disks or histories merely named in those reports. Those pending artifacts were not captured in this pass.

At the six inspected main tips, no blob matches any of the 37 `stash/` archive blobs. This is exact-content evidence, not proof that no paraphrases, links or equivalent implementation exist. The propagation proposed here is a pinned documentation pointer and repository-specific findings; implementation adoption remains a separate change.

## Repository findings and routing

The archive forks from `75cb31e59ccc4f436a428811cb70bbc495254821` and contains six additional commits, all changing only `stash/`. Current main adds two README/artwork commits to that same base. [Pinned main-to-stash comparison](https://github.com/timelabs-npo/rhea-project/compare/144a86065f8e10e2aba075cdb9e74199102f684d...3316bae0770744238099c25ae34e76e7ad4af8b4).

The archive chain is:
`d18ebeb201f0` capture → `4473717955fe` publication receipt → `619f9435e558` typed memory → `6ac41f6183e6` memory receipt → `41b6f6591033` experience register → `3316bae07707` experience receipt.

[Draft PR #33](https://github.com/timelabs-npo/rhea-project/pull/33) is the existing selective route for the WD provenance report. Its head `87e7e949e19a0b9b891ce0740d5f6f67b28c8a0f` is one commit ahead of `rhea-project-v2@accc8619b179539c3a775844f5f077fbad80715e`, changing exactly the report and evidence-index pointer. It remains open and unmerged in this snapshot. Its annotated report has a different blob from the immutable archive original, as the publication receipt documents. This PR adds a main-branch navigation record; it does not replace or merge #33.

The v2 source pin remains [omnia-vault@f5995536 source declaration](https://github.com/timelabs-npo/rhea-project/blob/accc8619b179539c3a775844f5f077fbad80715e/v2/03_omnia_lit/SOURCE.json). Archive preservation grants no v2 admission or executed acceptance.

Three ancestry findings prevent accidental bulk recovery:

- `stage4-release` is 482 commits ahead and 274 behind main. `grok-mem0-native-identity` is exactly 42 commits ahead of that stage4 tip, with no commits behind it. [Stage4-to-Grok ancestry](https://github.com/timelabs-npo/rhea-project/compare/fbf45a83dbfc0cbf39a23e7fe4048fc2a35e3a08...6c6a4c8a71516ab973c50215478dc5bbd6ad426f).
- `nexus-metadata-layer` and `copilot/find-context-window-traces` have the identical head `ebee5e0ab59ea4e66b26c7d607b2880ae25db624`. Treat them as two names for one current snapshot.
- `entire/checkpoints/v1` has no common ancestor with main according to the compare API. Preserve it as a separate history; it is not a normal feature-branch merge candidate.

Route the preservation procedure and experience catalog by pinned links to Omnia Playbook; route audit/runtime qualification material to Omnia Vault; route binary/provenance observations to MBSD and Blueshoes. Keep the full archival branch and old release histories separate from component implementation baselines.

## Branch ledger

Pinned main: `144a86065f8e10e2aba075cdb9e74199102f684d`. Ahead/behind counts measure commit ancestry relative to that main. They do not measure missing patches, successful tests or merge readiness. Historical merged PRs can refer to older heads, or contain content integrated without the original ancestry.

| Branch | Pinned head | Ahead / behind main | PR evidence |
| --- | --- | --- | --- |
| `codex/continuity-corpus-v1` | [`2f9868df11e2`](https://github.com/timelabs-npo/rhea-project/commit/2f9868df11e248d0fa5148054d46f496fba8aa61) | 31 / 2 | [#31](https://github.com/timelabs-npo/rhea-project/pull/31) open |
| `copilot/find-context-window-traces` | [`ebee5e0ab59e`](https://github.com/timelabs-npo/rhea-project/commit/ebee5e0ab59ea4e66b26c7d607b2880ae25db624) | 2 / 2 | none in retrieved PR history |
| `copilot/revise-visualization-concept` | [`75cb31e59ccc`](https://github.com/timelabs-npo/rhea-project/commit/75cb31e59ccc4f436a428811cb70bbc495254821) | 0 / 2 | none in retrieved PR history |
| `copilot/update-rhea-project-repo-link` | [`b808683f9158`](https://github.com/timelabs-npo/rhea-project/commit/b808683f91587b70119df3ea76f20bd7d1df7ac5) | 1 / 2 | [#16](https://github.com/timelabs-npo/rhea-project/pull/16) open draft |
| `dependabot/cargo/rhea-atlas/src-tauri/tauri-2.11.1` | [`8fc93666ffba`](https://github.com/timelabs-npo/rhea-project/commit/8fc93666ffbab129de697cb72f58f36a4eb0a4d4) | 1 / 2 | [#26](https://github.com/timelabs-npo/rhea-project/pull/26) open |
| `dependabot/cargo/tools/rhea-cc/openssl-0.10.80` | [`e54669db8c83`](https://github.com/timelabs-npo/rhea-project/commit/e54669db8c83249dd6194ad8a07f0172ac0e49f5) | 1 / 2 | [#28](https://github.com/timelabs-npo/rhea-project/pull/28) open |
| `dependabot/cargo/tools/rhea-cc/rustls-webpki-0.103.13` | [`964c4f5eb12b`](https://github.com/timelabs-npo/rhea-project/commit/964c4f5eb12b7684a3669c5d51fcb647702ad3eb) | 1 / 2 | [#23](https://github.com/timelabs-npo/rhea-project/pull/23) open |
| `dependabot/npm_and_yarn/rhea-atlas/flatted-3.4.2` | [`68bb1d3c9757`](https://github.com/timelabs-npo/rhea-project/commit/68bb1d3c97578132a297145a058de80aa2ca70c0) | 1 / 2 | [#18](https://github.com/timelabs-npo/rhea-project/pull/18) open |
| `dependabot/npm_and_yarn/rhea-atlas/multi-bf05dc1ecf` | [`78b8e2757977`](https://github.com/timelabs-npo/rhea-project/commit/78b8e2757977370dad8153ea7d1c56ed1ea197f8) | 1 / 2 | [#20](https://github.com/timelabs-npo/rhea-project/pull/20) open |
| `dependabot/npm_and_yarn/rhea-atlas/multi-e0866573e2` | [`6b858c52d7f3`](https://github.com/timelabs-npo/rhea-project/commit/6b858c52d7f3566164fcfd9ce83ecd6914900519) | 1 / 2 | [#24](https://github.com/timelabs-npo/rhea-project/pull/24) open |
| `dependabot/npm_and_yarn/rhea-atlas/next-15.5.18` | [`4b0fc7abbf4d`](https://github.com/timelabs-npo/rhea-project/commit/4b0fc7abbf4d4407980681999d36a8283b2cee3a) | 1 / 2 | [#27](https://github.com/timelabs-npo/rhea-project/pull/27) open |
| `dependabot/npm_and_yarn/rhea-atlas/postcss-8.5.10` | [`3a1c66925c6a`](https://github.com/timelabs-npo/rhea-project/commit/3a1c66925c6ac6c7f24dcf8e541c0f2fe204e975) | 1 / 2 | [#29](https://github.com/timelabs-npo/rhea-project/pull/29) open |
| `docs/wd-provenance-2026-09-06` | [`87e7e949e19a`](https://github.com/timelabs-npo/rhea-project/commit/87e7e949e19a0b9b891ce0740d5f6f67b28c8a0f) | 3 / 2 | [#33](https://github.com/timelabs-npo/rhea-project/pull/33) open draft |
| `entire/checkpoints/v1` | [`0d7b0d78e15f`](https://github.com/timelabs-npo/rhea-project/commit/0d7b0d78e15f005d17b92f62cd4fc6594c688089) | no common ancestor | none in retrieved PR history |
| `grok-mem0-native-identity` | [`6c6a4c8a7151`](https://github.com/timelabs-npo/rhea-project/commit/6c6a4c8a71516ab973c50215478dc5bbd6ad426f) | 524 / 274 | none in retrieved PR history |
| `hyperion/memory` | [`69f2f7dfa873`](https://github.com/timelabs-npo/rhea-project/commit/69f2f7dfa8739334478ea87114badd36d653e419) | 20 / 286 | [#11](https://github.com/timelabs-npo/rhea-project/pull/11) merged (older head); [#10](https://github.com/timelabs-npo/rhea-project/pull/10) merged (older head) |
| `main` | [`144a86065f8e`](https://github.com/timelabs-npo/rhea-project/commit/144a86065f8e10e2aba075cdb9e74199102f684d) | 0 / 0 | none in retrieved PR history |
| `nexus-metadata-layer` | [`ebee5e0ab59e`](https://github.com/timelabs-npo/rhea-project/commit/ebee5e0ab59ea4e66b26c7d607b2880ae25db624) | 2 / 2 | none in retrieved PR history |
| `research/persistent-state-corrigibility` | [`7989c7a94487`](https://github.com/timelabs-npo/rhea-project/commit/7989c7a94487ddf421812f6d2775c8b94352bd2b) | 3 / 2 | [#32](https://github.com/timelabs-npo/rhea-project/pull/32) open draft |
| `rhea-project-v2` | [`accc8619b179`](https://github.com/timelabs-npo/rhea-project/commit/accc8619b179539c3a775844f5f077fbad80715e) | 2 / 2 | none in retrieved PR history |
| `stage4-hardened` | [`c0d903419a88`](https://github.com/timelabs-npo/rhea-project/commit/c0d903419a88d4a88d71129b378b1110ac14ea52) | 6 / 271 | none in retrieved PR history |
| `stage4-release` | [`fbf45a83dbfc`](https://github.com/timelabs-npo/rhea-project/commit/fbf45a83dbfc0cbf39a23e7fe4048fc2a35e3a08) | 482 / 274 | [#14](https://github.com/timelabs-npo/rhea-project/pull/14) open |
| `stash` | [`3316bae07707`](https://github.com/timelabs-npo/rhea-project/commit/3316bae0770744238099c25ae34e76e7ad4af8b4) | 6 / 2 | none in retrieved PR history |

## Verification limits

All branch lists and PR lists fit within the 100-item first page. Comparisons cover every non-main branch. The checkpoint branch's explicit no-common-ancestor response is recorded as unrelated history. Recursive trees used for content identity checks were not truncated. GitHub comparison file lists can stop at 300 files; a 300-entry list is not a complete large-branch diff. No broad patch-equivalence analysis of the older Rhea histories was performed.

This pass used GitHub metadata, pinned trees, selected documents and local archive hashing. Component tests, builds, deployment checks, production runtime checks and pending WD artifact collection were not run. The archive's published Drive and scheduler receipts were read as historical records; those external states were not reverified or changed.
