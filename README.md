# NightShiftImd (SHIFT)

A fixed-supply ERC-20 for the IdentityMD custom-token launch. The only production
contract is [`src/NightShiftImd.sol`](src/NightShiftImd.sol).

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `NightShiftImd` |
| Token name | `NightShiftImd` |
| Symbol | `SHIFT` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Initial supply recipient | `msg.sender`, the immediate deploying account or factory |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun (Ethereum compatible) |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The constructor performs one mint and emits one
`Transfer(address(0), deployer, INITIAL_SUPPLY)` event. A direct deployment credits
the deploying account. A factory deployment credits the factory, never the
transaction origin, the token contract, or an application contract. The constructor
has no external calls, address dependencies, initialization step, or settings.

Deploy the creation bytecode of `src/NightShiftImd.sol:NightShiftImd` with no
arguments and no ETH. `forge inspect src/NightShiftImd.sol:NightShiftImd bytecode`
prints that bytecode locally. The launch service supplies the factory transaction
and any CREATE2 salt. No deployment or broadcast is performed by this project.
There are no separately deployed application contracts or linked libraries.

## Behavior and assumptions

The task specifies a name, symbol, precision and fixed supply; ordinary ERC-20
behavior is used for all other operations. OpenZeppelin Contracts v5.4.0 implements
balances, allowances, events, and ERC-6093 errors. The token has:

- Exact transfers, with no transfer fees, burns, reflections, or rebasing.
- `transfer`, `approve`, and `transferFrom` returning `true` on success and
  reverting on failure; failures preserve balances and allowances.
- Zero-amount transfers and transfers to oneself, with normal `Transfer` events.
- Rejection of zero-address recipients and zero-address spenders.
- Allowances scoped to each holder/spender pair. Finite allowances decrease on
  `transferFrom`; `type(uint256).max` is an unlimited allowance and does not decrease.
- `approve` replacing the allowance and emitting `Approval`. Spending an allowance
  through `transferFrom` does not emit an additional `Approval` event in this version.

No owner, administrator, minter, pauser, blacklist, confiscation, upgrade, permit,
external mint, or external burn capability exists. The deployer receives tokens
but has no special power over other holders. No callback runs on a recipient;
transfers to contracts are ordinary ERC-20 balance updates. Native ETH transfers
are rejected. Assets sent to the token contract have no recovery function.

## Launch and operational responsibilities

The intended launch is Ethereum (chain ID 1). The factory initially receives 100%
of the supply and performs the launch distribution itself: 10% to the launch's
MerkleDistributor, 80% for pool liquidity, and 10% as the requester's remainder.
The token does not perform or reserve any of these transfers in its constructor.
These percentages describe the supplied launch policy; they are not token-level
restrictions. The token does not need factory, distributor, or pool exemptions
because every transfer delivers the full amount.

The separate launch-manifest/deployment process owns the pair, pool configuration,
economics, distribution addresses, and transaction execution. It must record the
contract identifier, metadata, empty constructor arguments and exact base-unit
supply above. This project does not supply a `launch.json`.

### After launch

There are no owner setters, initialization calls, or ongoing administrative duties.
The launch operator should confirm the deployed bytecode and metadata, verify the
source on the chain explorer with the pinned build settings, and check the mint
event and factory distribution receipts. Subsequent transfers within the launch
transaction may leave the factory with no tokens even though it received the
complete initial mint.

Holders control their balances and approvals. Integrations should query
`allowance` directly, use limited approvals where practical, and account for the
standard ERC-20 approval replacement race: revoking an existing allowance before
granting a replacement reduces that exposure, but cannot undo a spend already
executed. No operator can recover mistaken transfers or freeze a compromised
holder's tokens.

## Local verification

All Solidity dependencies are vendored as ordinary files under `lib/`; no network,
submodules, package install, RPC endpoint, wallet, environment-derived addresses,
FFI, or filesystem cheatcode permissions are needed by the build or tests. Foundry
and the version-pinned Solidity compiler must already be available to an offline
verifier.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xfcd2978f5a58e3eafbcfa9b28be86da70bcaa5fdcb786b87a113d58c32853723 forge test
forge fmt --check
```

`foundry.toml` sets 1,024 cases per fuzz test and 256 invariant sequences of up to
64 calls. It does not pin a seed; the command above uses the assignment's verifier
seed. Tests deploy fresh local contracts and do not read or set environment variables.

- `test/NightShiftImd.t.sol` covers metadata, mint events, balances, transfer and
  approval events, zero values, self-transfers, contract recipients, approval
  replacement/revocation, unlimited allowances, invalid recipients, insufficient
  balances/allowances, rollback on failed transfers, unauthorized spending, absent
  administrative entrypoints, runtime opcode restrictions, and randomized amounts.
- `test/NightShiftImdLaunch.t.sol` checks CREATE2 deployment to a factory and exact
  distribution, claim, and pool-facing token movements. Its local actors simulate
  token movements; it does not implement or test an actual Uniswap v4 pool. The
  network's independent protected harness provides that integration check.
- `test/NightShiftImdInvariant.t.sol` checks fixed supply, conservation, and an
  independent balance/allowance ledger across randomized successful and failing
  transfers, approvals and delegated transfers, including self-transfers and
  invalid zero-address destinations.

The supplied security reference was reviewed against this contract's reachable
functions. Token operations make no external calls; only holders or their approved
spenders can move balances, and the constructor is the only reachable mint path.
Foundry unit, fuzz and invariant tests are the automated checks used here; Slither
and Mythril were not run. These checks are not an independent security audit.
Independent adversarial review remains part of the network's release process.

## Vendored dependencies

[`DEPENDENCIES.json`](DEPENDENCIES.json) records pinned upstream commits, archive
hashes and individual source hashes. Upstream source files are unmodified:

- OpenZeppelin Contracts `v5.4.0`, commit
  `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0`: the ERC-20 source and its four
  transitive imports, with its MIT license.
- forge-std `v1.9.7`, commit `77041d2ce690e692d6e03cc812b57d1ddaa4d505`:
  Solidity test utilities, with its Apache-2.0 and MIT licenses. Production code
  does not import forge-std.
