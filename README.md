# resolv-kontrol-audit

Symbolic (Kontrol) audit of the **Resolv** protocol (USR / RLP / stUSR / wstUSR),
focused on **permissionless critical fund-draining** paths.

This is intentionally isolated from the main scanning campaign: it runs under the
`artsbykriss` account so it never consumes the main campaign's runners or quota.

## Layout

```
contracts/                 reconstructed verified sources (98 Resolv contracts + live impls)
  layerzero/SimpleOFTAdapter.sol   LayerZero OFT adapter wrapper
lib/                       pinned deps (openzeppelin-contracts/-upgradeable, chainlink, aave, forge-std)
node_modules/              LayerZero deps installed via `npm install` (gitignored)
test/                      Kontrol property suites
  harness/ResolvHarness.sol  shared upgradeable-proxy deployment harness
  mocks/                     MockERC20 / MockUSR / MockTreasury / MockChainlink / MockUsrPriceStorage
  StUSR.t.sol                W2 — rebasing share math
  WstUSR.t.sol               W2 — ERC-4626 wrapper + blacklist
  UsrRedemption.t.sol        W1 — redemption pricing, limits, treasury interaction
  W4_Requests.t.sol          W4 — request managers / TheCounter (arbitrary-mint class)
  W3_Staking.t.sol           W3 — ResolvStakingV2 / silo
  W5_Coordinator.t.sol       W5 — ExternalRequestsCoordinator / Treasury composition
  W6_OFT.t.sol               W6 — LayerZero OFT adapter (permissionless send)
  PriceStorage.t.sol         W8 — oracle price bounds
kontrol.toml               Kontrol build/prove settings
.github/workflows/kontrol.yml   proof matrix (one job per suite)
PROPERTIES.md              full English property specification (W1–W8, X)
```

## Properties covered

| Suite | Properties |
|---|---|
| `StUSR_Test` | W2-P1..P7, W7-P1/P3 |
| `WstUSR_Test` | W2-P8..P14, W7-P1/P2/P3 |
| `UsrRedemption_Test` | W1-P1..P10 |
| `W4_Requests_Test` | W4-P1..P6 (incl. documented arbitrary-mint vulnerabilities) |
| `W3_Staking_Test` | W3-P1/P2/P6 |
| `W5_Coordinator_Test` | W5-P1..P5 (recipient, allowance, protocol-token burn) |
| `W6_OFT_Test` | W6-P1..P4 (send bounded by balance/allowance, owner-gated config) |
| `PriceStorage_Test` | W8-P1 |

See `PROPERTIES.md` for the full specification. All 59 properties pass under
256-run concrete fuzzing (`forge test`).

## Run locally (compile + fast fuzz pre-check)

```bash
npm install          # LayerZero deps (for the OFT adapter)
forge build
forge test
```

## Run the proofs

Dispatch the `kontrol` workflow (or push to `main`). Each suite is a separate job
using `runtimeverificationinc/kontrol:ubuntu-jammy-1.0.255`; the job installs the
LayerZero JS deps, makes the workspace writable (the container runs as root),
builds, then proves the suite. Verdicts and logs are uploaded as artifacts.

## Known vulnerabilities encoded

The 2026-03-22 exploit class is encoded as passing "KNOWNVULN" assertions so the
suite documents it rather than failing:

- `W4-P5` `TheCounter.completeSwap` — arbitrary `_targetAmount` mint (no ratio to deposit).
- `W4-P1` `UsrExternalRequestsManager.completeMint` — arbitrary `_mintAmount`.
- `W4-P2` `UsrExternalRequestsManager.completeBurn` — arbitrary treasury withdrawal.

These are `SERVICE_ROLE`-gated (privileged-key compromise), not permissionless.
The permissionless surfaces (W2/W3/W6) currently hold under 256-run fuzzing.
