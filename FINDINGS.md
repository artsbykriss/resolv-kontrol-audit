# Resolv — findings log (CHRIS/artsbykriss audit)

## FINDING-OFT-01 — `SimpleOFTAdapter` implementation is not `_disableInitializers`-protected
- **Severity:** Low / Informational (implementation initialization; not a direct fund drain).
- **Contract:** `contracts/layerzero/SimpleOFTAdapter.sol`
  ```
  contract SimpleOFTAdapter is OFTAdapterUpgradeable {
      constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {}
      function initialize(address _delegate) public initializer {
          __OFTAdapter_init(_delegate);
          __Ownable_init(_delegate);
      }
  }
  ```
- **Issue:** the constructor does **not** call `_disableInitializers()`. Every other upgradeable
  implementation in the repo does (`StUSR`, `WstUSR`, `UsrPriceStorage`, `ResolvStakingV2`,
  `ResolvStaking`, `SimpleToken`, `ResolvToken`, `Treasury`, connectors, oracles — confirmed by grep).
- **Impact:** any third party can call `initialize(address)` on the **bare implementation**, becoming
  its owner (`impl.owner()`), and set its delegate/peer state. The proxy's own storage is separate,
  so this does not by itself move funds; it is a hardening/defence-in-depth issue (and a footgun if
  the implementation is ever delegatecalled or reused).
- **Evidence (Kontrol property):** `test_W7P5_implInitUnprotected_KNOWNVULN` in `test/W6_OFT.t.sol`
  asserts `impl.initialize(0xBAD)` succeeds and `impl.owner() == 0xBAD`. Passes (vuln present).
- **Remediation:** add `constructor(...) { _disableInitializers(); }` to `SimpleOFTAdapter`
  (matching the other implementations).

## Status
- W1/W2/W3/W4/W5/W6/W7/W8 properties are implemented and pass **concretely** (`forge test`: 69/69).
  The Kontrol proof matrix verdicts come from CI on `artsbykriss/resolv-kontrol-audit`.
- The previous Kontrol run's FAILs were all **spurious** (inline-initializer-zero artifact, fixed by
  making test addresses `constant`).
- No permissionless fund-drain has been found so far; FINDING-OFT-01 is the only real (low) finding
  from the new high-risk properties.
