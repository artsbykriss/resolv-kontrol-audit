# Resolv — Kontrol property specification

Every property below is a proof obligation for Kontrol. Format:
`ID | target | entry point | property | class (P=permissionless, G=gated) | falsification`.

Assumes: `USR` decimals 18; `PRICE_SCALING_FACTOR = 1e18`; token decimals 6 or 18; roles as deployed.
"Trusted price" means the Chainlink feed / `UsrPriceStorage` input — oracle *correctness* is W8, not assumed here.

---

## W1 — USR redemption pricing & limits  (`UsrRedemptionExtension` + `UsrExternalRequestsManager`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W1-P1 | extension | `redeem(amount, receiver, token)` | Any successful call burns exactly `amount` USR from `msg.sender` and pays `receiver` at most `amount*10^(dTok-dUSR)/price` (floor), never more. | G (manager) / P if whitelist off | payout > entitlement by ≥1 unit |
| W1-P2 | extension | `redeem` | `currentRedemptionUsage` increases by exactly `amount`; the sum of successful redemptions since the last reset never exceeds `redemptionLimit`. | G/P | usage/limit exceeded, or under-counting |
| W1-P3 | extension | `redeem` | The 24h reset only moves `lastResetTime` forward by whole periods and can never *increase* remaining allowance (no reset abuse). | G/P | usage reset within a period, or lastResetTime moved back |
| W1-P4 | extension | `redeem` | No caller's USR or withdrawal-token balance can increase by more than the computed entitlement (no self-mint). | G/P | balance gain > entitlement |
| W1-P5 | extension | `redeem` | Rounding is **floor** everywhere and never favours the redeemer (sum of parts ≤ whole). | G/P | round-up in user's favour |
| W1-P6 | extension | `redeem` | If `USR_price == PRICE_SCALING_FACTOR` and Chainlink price `p`, payout == `amount` (1:1) modulo ≤1 unit. | G/P | deviation > 1 unit |
| W1-P7 | extension | `redeem` | Reverts (no state change) when USR price is stale (`now > ts + heartbeat`) or `< PRICE_SCALING_FACTOR`. | G/P | value transferred on stale/invalid price |
| W1-P8 | manager | `redeem` | A caller failing `onlyAllowedProviders` cannot cause any treasury `safeTransfer`/`aaveBorrow`. | P (protection) | non-whitelisted caller moves treasury value |
| W1-P9 | extension | `redeem` | `treasury.aaveBorrow` is only called when `treasuryBalance < payout`, and the amount borrowed equals exactly the shortfall. | G/P | over-borrow / borrow without shortfall |
| W1-P10 | extension | `redeem` | `Treasury.increaseAllowance` is granted exactly `payout` and fully consumed by the transfer in the same tx (no residual allowance). | G/P | leftover allowance after redeem |

## W2 — stUSR / wstUSR share math  (`ERC20RebasingUpgradeable`, `StUSR`, `WstUSR`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W2-P1 | StUSR | `convertToShares`/`convertToAssets` | `convertToShares(convertToAssets(s)) ≤ s` (no share round-trip gain). | P | shares gained |
| W2-P2 | StUSR | `convertToAssets`/`convertToShares` | `convertToAssets(convertToShares(u)) ≤ u` (no asset round-trip gain). | P | assets gained |
| W2-P3 | StUSR | `deposit`→`withdraw` | A full `deposit(u)` then `withdraw` of the resulting entitlement returns ≤ `u` (net value never increases). | P | net > u |
| W2-P4 | StUSR | `deposit` | If `previewDeposit(u) == 0` the call reverts (no silent donation to the pool). | P | successful 0-share deposit |
| W2-P5 | StUSR | `transfer`/`transferFrom` | The shares moved equal `convertToShares(value)` (floor); the USR-denominated allowance consumed ≤ `value`; the recipient's USR-equivalent gain ≤ `value`. | P | recipient gain > value, or sender loss > value |
| W2-P6 | StUSR | donation | Direct USR donation to the vault can only *increase* the per-share value; an attacker cannot convert a donation into a net gain via deposit/transfer round-trips against other holders. | P | attacker net USR out > net in |
| W2-P7 | StUSR | invariant | `totalAssets() == usr.balanceOf(stUSR)` and `totalShares() == sum of all share balances` are preserved by every state-changing function. | P | desync |
| W2-P8 | wstUSR | `deposit`/`mint`/`withdraw`/`redeem` | `deposit(u)` then `redeem(all)` returns ≤ `u`; `mint(w)` then `redeem(w)` returns ≤ cost. | P | net gain |
| W2-P9 | wstUSR | `unwrap`/`wrap` | `wrap(s)` then `unwrap` returns ≤ `s` stUSR shares; `unwrap(w)` transfers exactly `w*ST_USR_SHARES_OFFSET` stUSR shares and burns exactly `w` wstUSR (no mismatch). | P | stUSR received > shares burned×1000 |
| W2-P10 | wstUSR | invariant | `totalAssets() == stUSR.convertToUnderlyingToken(totalSupply()*1000)` preserved by all permissionless ops. | P | desync |
| W2-P11 | wstUSR | `deposit`/`wrap` | If `previewDeposit(u) == 0` (or `convertToShares(s)==0`) the input must not be silently retained *and* the caller must gain no advantage; equivalently no profitable 0-mint path. | P | profitable 0-mint |
| W2-P12 | wstUSR | `previewMint`/`previewRedeem` | The `(totalSupply+1)/(totalShares+1000)` offsets are consistent with stUSR's own curve: `previewRedeem(previewMint(w)) ≥ w - 1` cannot imply a gain (rounding favours the vault). | P | round-trip gain |
| W2-P13 | wstUSR(V2) | `burnFromBlacklist` | Only callable with `BLACKLISTER_ROLE`; burns exactly the blacklisted account's wstUSR and the corresponding USR; leaves `totalAssets`/`totalSupply` consistent and cannot be used on a non-blacklisted account. | G | burn of non-blacklisted, or insolvency |
| W2-P14 | wstUSR(V2) | `_update` | A blacklisted `from`/`to` can never move value; blacklist cannot be bypassed via `wrap`/`unwrap`/`mint`. | G | blacklisted transfer succeeds |

## W3 — ResolvStakingV2 / Silo  (`ResolvStakingV2`, `ResolvStakingSilo`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W3-P1 | staking | `deposit`→`initiateWithdrawal`→`withdraw` | Returns ≤ deposited RESOLV (no principal gain). | P | net gain |
| W3-P2 | staking | invariant | The silo's RESOLV balance ≥ Σ pending withdrawals. | P | payout exceeds silo funds |
| W3-P3 | staking | `depositReward`/`claim` | Σ claimed rewards ≤ Σ deposited rewards (no over-distribution). | P (claim) | phantom rewards |
| W3-P4 | staking | `transfer`/`transferFrom` | Checkpointing keeps Σ effective balances ≤ total staked; transfers create no reward entitlement. | P | effective-sum inflation |
| W3-P5 | staking | `claim` w/ delegatee | A delegatee cannot cause `receiver` to receive more than the user's accrued rewards. | P | over-claim |
| W3-P6 | staking | `withdraw` | Cannot withdraw before cooldown or withdraw more than the pending amount. | P | early/over withdrawal |

## W4 — Request managers: arbitrary-amount mint/burn  (`UsrExternalRequestsManager`, `ExternalRequestsManager`, `TheCounter`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W4-P1 | usr manager | `completeMint` | `_mintAmount` must be a function of `request.amount` and trusted price, bounded by an explicit invariant: no request can mint more than `request.amount` converted at any reasonable price (i.e. cannot mint unbacked USR). | G | arbitrary mint accepted |
| W4-P2 | usr manager | `completeBurn` | `_withdrawalAmount` paid from Treasury is bounded by the USR burned at the trusted price. | G | over-withdrawal |
| W4-P3 | usr manager | `completeMint`/`completeBurn` | A request can be completed at most once; state transitions CREATED→COMPLETED only. | G | double-complete |
| W4-P4 | usr manager | `emergencyWithdraw` | Only admin; cannot be reached by a request lifecycle. | G | non-admin sweep |
| W4-P5 | TheCounter | `completeSwap` | `simpleToken.mint(_targetAmount)` is bounded by `request.amount` and `fee`; no arbitrary mint (the exact bug of 2026-03). | G | arbitrary mint |
| W4-P6 | TheCounter | `requestSwap`/`cancelSwap` | A user can always cancel a CREATED request and recover exactly `request.amount`; completion cannot front-run cancellation to steal the deposit. | P | deposit lost |

## W5 — Coordinator / Treasury composition  (`ExternalRequestsCoordinator`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W5-P1 | coordinator | `completeBurn` | The Treasury→provider `safeTransferFrom` via manager allowance cannot send value to an address outside the Treasury recipient whitelist. | G | whitelist bypass |
| W5-P2 | coordinator | `completeBurn` | The manager allowance granted equals the withdrawal amount and is fully consumed (no residual). | G | residual allowance |
| W5-P3 | coordinator | `completeMint` | Burning the protocol token from Treasury is matched 1:1 by the deposit received. | G | unbalanced burn |

## W6 — OFT adapters (permissionless `send`)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W6-P1 | SimpleOFTAdapter | `send`/`sendFrom` | Cannot move more than sender balance/allowance; adapter's locked-token accounting stays ≥ outstanding. | P | over-send |
| W6-P2 | SimpleOFTAdapter | `setPeer` | Only owner can set a peer; a malicious peer cannot be set permissionlessly. | G | peer hijack |

## W7 — Initialization

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W7-P1 | all upgradeables | `initialize` | Reverts if already initialized (proxy) — no re-initialization by an attacker. | P | second init |
| W7-P2 | wstUSR(V2) | `initializeV2` | `reinitializer(2)` runs at most once and only for the intended proxy. | P | second initV2 |
| W7-P3 | implementations | `initialize` | Direct implementation `initialize` always reverts (`_disableInitializers`). | P | impl initialized |

## W8 — Price storage / oracle inputs

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W8-P1 | UsrPriceStorage | `setReserves` | The stored price respects `[lowerBound, upperBound]`; cannot be set outside bounds. | G | out-of-bounds stored |
| W8-P2 | RlpPriceStorage | `setPrice` | Same bounds enforcement for RLP (and monotonicity for UpOnly). | G | out-of-bounds / decrease on UpOnly |
| W8-P3 | ChainlinkOracle | `getLatestRoundData` | Reverts or is treated stale when `updatedAt` older than heartbeat; cannot return a non-positive price as valid. | G | stale accepted by consumer |

---

## Cross-cutting invariants (protocol-level)

| ID | Invariant | Class |
|---|---|---|
| X-P1 | No permissionless entry point can increase the caller's net value at the protocol's expense (sum of all token balances of the protocol + users is conserved). | P |
| X-P2 | Every function that moves value is either permissionless-and-bounded or role-gated; no third path exists. | P |
| X-P3 | The protocol's token balances (StUSR, WstUSR, Treasury, Manager) are always ≥ the sum of user entitlements. | P |
| X-P4 | A paused contract performs no state change (only views). | P |

## Test-plan mapping

| File | Properties |
|---|---|
| `test/StUSR.t.sol` | W2-P1..P7, W7-P1/P3 |
| `test/WstUSR.t.sol` | W2-P8..P13, W7-P1/P2/P3 |
| `test/UsrRedemption.t.sol` | W1-P1..P10, W8-P3 |
| `test/UsrRequestsManager.t.sol` | W4-P1..P4, X-P4 |
| `test/TheCounter.t.sol` | W4-P5/P6 |
| `test/ResolvStakingV2.t.sol` | W3-P1..P6 |
| `test/Coordinator.t.sol` | W5-P1..P3 |
| `test/PriceStorage.t.sol` | W8-P1/P2 |
| `test/OFT.t.sol` | W6-P1/P2 |
| `test/Invariants.t.sol` | X-P1..P4 |

**Priority order for the first proof run:** W2 (permissionless, no roles) → W1 → W4 → W3.

---

## Round 2 additions (high-risk permissionless coverage)

| ID | Target | Entry | Property | Class | Falsify by |
|---|---|---|---|---|---|
| W3-P3 | staking | `claim` | An account with no stake cannot claim any reward (no free reward). | P | attacker with 0 stake gains reward tokens |
| W3-P4 | staking | `claim` | A staker's claim never exceeds the amount deposited into the reward pool. | P | over-distribution > deposit |
| W3-P5 | staking | `claim` | Rewards cannot be claimed twice for the same accrual. | P | second claim gains > 0 |
| W6-P5 | SimpleOFTAdapter | `lzReceive` | Only the LayerZero endpoint can drive the receive path (no permissionless unlock). | P | non-endpoint call reaches `_credit` |
| W6-P6 | SimpleOFTAdapter | `lzReceive` | Even the endpoint cannot credit from an unconfigured peer/origin. | P | unknown peer accepted |
| W6-P7 | SimpleOFTAdapter | `send` | Every send increases the adapter's locked balance by exactly `amountSent` (never decreases). | P | adapter lock mismatch / under-backing |
| W7-P4 | UsrPriceStorage | `initialize` | Bare implementation cannot be initialized (`_disableInitializers`). | P | impl initialized |
| W7-P5 | SimpleOFTAdapter | `initialize` | Bare implementation cannot be initialized. | P | **FAILS — see FINDING-OFT-01** |
| W7-P6 | ResolvStakingV2 | `initialize` | Bare implementation cannot be initialized. | P | impl initialized |
| W7-P7 | StUSR | `initialize` | Bare implementation cannot be initialized. | P | impl initialized |

### Test mapping (round 2)
| File | New properties |
|---|---|
| `test/W3_Staking.t.sol` | W3-P3/P4/P5, W7-P6 |
| `test/W6_OFT.t.sol` | W6-P5/P6/P7, W7-P5 |
| `test/StUSR.t.sol` | W7-P7 (`test_W7P3_implInitRevertsStUSR`) |
| `test/PriceStorage.t.sol` | W7-P4 (`test_W7P4_implInitRevertsPriceStorage`) |

### Still-uncovered (documented gaps — NOT passes)
- Staking effective-balance **boost gaming** across multi-step deposit/withdraw cycles (needs a
  stateful/BMC property; current reward tests are per-call only).
- OFT **receive-path value flow** with an *authentic* endpoint/peer (our endpoint is a mock; we only
  prove the endpoint/peer gating, not the credit accounting).
- **Malicious/fee-on-transfer/reentrant withdrawal token** in `redeem` (SERVICE-gated, so lower risk).
- **Permit** (`depositWithPermit`) replay/malleability.
- **Blacklist bypass** via `approve`+`transferFrom` / `wrap` / `unwrap`.
- **wstUSR-specific donation/inflation** (only stUSR `W2P6` executed).
- A true **X-P1 attacker-profit** goal with the **real** USR/RLP token (mocks are free-mint).
