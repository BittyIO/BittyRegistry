# Bitty Guard

On-chain registry of allowed assets, DeFi protocols, and vault implementations for [Bitty](https://github.com/BittyIO) vaults. The guard is the source of truth for what tokens vaults may hold, which external protocols they may interact with, and which implementations they may upgrade to.

| Chain   | Address |
|---------|---------|
| Mainnet | [`0x00580099D09E00E5920000D032260060E527DC60`](https://etherscan.io/address/0x00580099D09E00E5920000D032260060E527DC60) |
| Base    | [`0x00580099D09E00E5920000D032260060E527DC60`](https://basescan.org/address/0x00580099D09E00E5920000D032260060E527DC60) |
| Sepolia | [`0x00580099D09E00E5920000D032260060E527DC60`](https://sepolia.etherscan.io/address/0x00580099D09E00E5920000D032260060E527DC60) |

Mainnet and Base share the same CREATE2 address. Sepolia was deployed against a different init-code hash and therefore landed elsewhere.

## Overview

`BittyV1Guard` maintains three registries:

| Registry | Lifecycle | Effect |
|----------|-----------|--------|
| **Assets** | Add / remove | Removed assets can only be sold, not bought |
| **Protocols** | Add / deprecate | Deprecated protocols are exit-only — existing positions can be withdrawn, but no new deposits |
| **Implementations** | Register / unregister | A vault may only UUPS-upgrade to a registered implementation; unregistering blocks it as a *future* target but does not affect vaults already running it |

There is no separate stable-coin registry. A stable coin is an asset registered with the stable-coin category; callers distinguish token types by reading `assetCategory`.

The implementation registry is what makes vault upgrades governance-gated: each vault's `_authorizeUpgrade` reads `isImplementationRegistered(newImpl)`, so no vault can upgrade to code the guard has not blessed. Registration here is immediate — the upgrade **delay** lives in governance (the `IMPLEMENTATION_MANAGER_ROLE` holder is a `TimelockController`), not in this contract.

Both registries store a `uint8` category per entry, supplied by the caller at registration time. The guard rejects category `0` (treated as "skip this entry") and does not interpret any other value — meaning is a convention shared with vaults and other consumers. Category `0` on read means the address was never registered.

### Category conventions

Asset and protocol categories are independent namespaces (the same number can mean different things in each registry).

**Assets** (as used in deploy scripts):

| Value | Meaning |
|-------|---------|
| `1` | Stable coin |
| `2` | Crypto |

**Protocols** (as used in tests; vault-side convention):

| Value | Meaning |
|-------|---------|
| `1` | Lending |
| `2` | Staking |
| `3` | AMM |
| `4` | Intent |

## Access control

Administration uses OpenZeppelin `AccessControlDefaultAdminRules` with a 7-day delay on `DEFAULT_ADMIN_ROLE` transfers.

| Role | Scope |
|------|-------|
| `DEFAULT_ADMIN_ROLE` | Role grants, initialization |
| `ASSET_MANAGER_ROLE` | Asset registry |
| `PROTOCOL_MANAGER_ROLE` | Protocol registration / deprecation, all protocol categories |
| `IMPLEMENTATION_MANAGER_ROLE` | Implementation registry (register / unregister vault upgrade targets) |

One role per registry: what a vault may **hold**, what it may **use**, and what it may **upgrade to**.

A holder of `PROTOCOL_MANAGER_ROLE` can register any protocol category. Per-category manager roles existed in an earlier design; if separate custody is needed again, that would mean restoring per-category roles rather than hiding checks inside the current ones.

`IMPLEMENTATION_MANAGER_ROLE` is kept **deliberately separate** from the asset/protocol roles because blessing an implementation is the highest-blast-radius privilege — every vault can upgrade to it, so a bad entry can drain them all. It is meant to be held by a governance `TimelockController`, giving upgrades a delay while asset/protocol management stays fast and operational. At deploy the constructor grants all three roles to `DEPLOYER` as a launch bootstrap (so it can register the first implementation before governance is stood up); the intended hand-off is to **revoke `IMPLEMENTATION_MANAGER_ROLE` from the deployer and grant it to the timelock** once governance is live. `DEFAULT_ADMIN_ROLE` can perform that grant/revoke at any time.

## Deployment

The guard is deployed through [ImmutableCreate2Factory](https://github.com/ProjectOpenSea/seaport/blob/main/docs/ImmutableCreate2Factory.md) (`0x0000000000FFe8B47B3e2130213B802212439497`) with a deployer-prefixed salt, so only the designated deployer can land the contract at the target address. The constructor takes no arguments, which keeps init code identical across chains and makes the CREATE2 address chain-independent.

Only `tx.origin == DEPLOYER` (`0x12EE2de7BF086388B1D560eb95e7191Edfab9823`) may deploy the contract.

Per-chain token addresses and the guard address live in `deployments/*.toml`. Initial registry contents differ by chain — for example Base registers cbBTC rather than bridged WBTC because of liquidity depth.

### Deploy to a chain

Set environment variables:

```shell
export ALCHEMY_KEY=...
export ETHERSCAN_API_KEY=...
export PRIVATE_KEY=...
```

Then broadcast the chain script (Foundry selects the fork from `deployments/<chain>.toml`):

```shell
# Sepolia
forge script script/BittyV1GuardSepolia.s.sol:Deploy --broadcast -vvvv

# Mainnet
forge script script/BittyV1GuardMainnet.s.sol:Deploy --broadcast -vvvv

# Base
forge script script/BittyV1GuardBase.s.sol:Deploy --broadcast -vvvv
```

Verify on Etherscan:

```shell
forge verify-contract \
  --chain-id 1 \
  0x00D4000023b177003fb1bF1d3160BaefF5c60000 \
  src/BittyV1Guard.sol:BittyV1Guard \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## Development

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```shell
git clone git@github.com:BittyIO/guard.git
cd guard
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

Solidity `0.8.34`, optimizer enabled (`runs = 10000`, `via_ir = true`).

## Key API

```solidity
// One-time setup after deploy
function initialize(
    address[] calldata assets,
    uint8[] calldata assetCategories,
    address[] calldata protocols,
    uint8[] calldata protocolCategories
) external;

// Assets — every asset carries a category; stable coins use category 1
function addAssets(address[] calldata, uint8[] calldata categories) external;
function removeAssets(address[] calldata) external;
function isAssetRegistered(address) external view returns (bool);
function assetCategory(address) external view returns (uint8);

// Protocols — category is supplied by the caller and recorded
function addProtocols(address[] calldata, uint8[] calldata categories) external;
function deprecateProtocols(address[] calldata) external;
function isProtocolRegistered(address) external view returns (bool);
function isProtocolDeprecated(address) external view returns (bool);
function protocolCategory(address) external view returns (uint8);

// Implementations — vault UUPS upgrade targets (IMPLEMENTATION_MANAGER_ROLE)
function registerImplementations(address[] calldata) external;
function unregisterImplementations(address[] calldata) external;
function isImplementationRegistered(address) external view returns (bool);

// Events — the only enumeration mechanism
event AssetAdded(address indexed assetAddress, uint8 indexed category);
event AssetRemoved(address indexed assetAddress);
event ProtocolAdded(address indexed protocolAddress, uint8 indexed category);
event ProtocolDeprecated(address indexed protocolAddress);
event ImplementationRegistered(address indexed implementation);
event ImplementationUnregistered(address indexed implementation);
```

### Errors

| Error | When |
|-------|------|
| `NotDeployer()` | Constructor called with `tx.origin != DEPLOYER` |
| `LengthMismatch()` | Address and category arrays differ in length |
| `NotRegisteredProtocol(address)` | `deprecateProtocols` targets an address that is not registered |

### Design notes

**No bulk reads.** Membership is stored in `mapping(address => bool)`, so the guard answers "is this registered?" in one `SLOAD` but cannot return all members. Consumers that need the full set replay the events above from the deployment block and apply adds/removes in order. Events fire only on actual state changes, so a replay never double-counts.

**Re-adding.** Registering an asset or protocol that is already active with the same category is a no-op (no event). Re-registering a deprecated protocol clears its deprecation flag.

**Stable coins.** There is no `isStableCoinRegistered` — check `isAssetRegistered(token) && assetCategory(token) == 1` (or whatever stable-coin category your deployment uses).

**Implementations.** Like the other registries, membership is a `mapping(address => bool)` with `ImplementationRegistered` / `ImplementationUnregistered` events for replay; registering an already-registered impl (or unregistering an absent one) is a no-op. Unregistering only removes it as a *future* upgrade target — vaults already running it are untouched. The registry is intentionally minimal (no category, no timelock); the review delay is enforced by the governance `TimelockController` that holds `IMPLEMENTATION_MANAGER_ROLE`.

See [`IBittyV1Guard.sol`](src/interfaces/IBittyV1Guard.sol) for full NatSpec.

## Project layout

```
src/
  BittyV1Guard.sol          # Registry contract
  interfaces/
    IBittyV1Guard.sol       # Public interface
script/
  BaseDeploy.sol            # Shared deploy harness (TOML config, address persistence)
  BittyV1GuardMainnet.s.sol
  BittyV1GuardBase.s.sol
  BittyV1GuardSepolia.s.sol
deployments/
  mainnet.toml              # Chain-specific token addresses
  base.toml
  sepolia.toml
test/
  local/BittyV1Guard.t.sol  # Unit tests — asset / protocol / implementation registries
```

## License

AGPL-3.0-only
