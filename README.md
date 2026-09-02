# Bitty Guard

On-chain registry of allowed assets, DeFi protocols, and account implementations for [Bitty](https://github.com/BittyIO) vaults. The guard is the source of truth for what tokens vaults may hold, which external protocols they may interact with, and which implementations they may upgrade to.

| Chain   | Address |
|---------|---------|
| Mainnet | [`0x0000000300FBc66e003a60Bb635789709ce0Eadb`](https://etherscan.io/address/0x0000000300FBc66e003a60Bb635789709ce0Eadb) |
| Base    | [`0x0000000300FBc66e003a60Bb635789709ce0Eadb`](https://basescan.org/address/0x0000000300FBc66e003a60Bb635789709ce0Eadb) |
| Sepolia | [`0x0000000008889521Db10f4c1eb20eF49179b498C`](https://sepolia.etherscan.io/address/0x0000000008889521Db10f4c1eb20eF49179b498C) |

Mainnet and Base share the same CREATE2 address. Sepolia was deployed against a different salt and therefore landed elsewhere.

These are **proxy** addresses. The guard is a UUPS proxy, so the address above is what vaults compile in and never changes; the implementation behind it does.

## Overview

`BittyV1Guard` maintains three registries:

| Registry | Lifecycle | Effect |
|----------|-----------|--------|
| **Assets** | Add / remove | Removed assets can only be sold, not bought |
| **Protocols** | Add / deprecate | Deprecated protocols are exit-only — existing positions can be withdrawn, but no new deposits |
| **Implementations** | Set / retire | An account may only UUPS-upgrade to the current or a past implementation of its category; retiring one blocks it as a *future* target but does not affect accounts already running it |

There is no separate stable-coin registry. A stable coin is an asset registered with the stable-coin category; callers distinguish token types by reading `assetCategory`.

The implementation registry is what makes account upgrades governance-gated: each account's `_authorizeUpgrade` asks `isImplementationRegisteredFor(newImpl, category)`, so no account can upgrade to code the guard has not blessed. Registration here is immediate — the upgrade **delay** lives in governance (the `IMPLEMENTATION_MANAGER_ROLE` holder is a `TimelockController`), not in this contract.

Every registry entry carries a `uint8` category supplied by the caller. The guard rejects category `0` (treated as "skip this entry" for assets and protocols, and as an error for implementations) and does not interpret any other value — meaning is a convention shared with vaults and other consumers. Category `0` on read means the address was never registered.

### Category conventions

The three category namespaces are independent — the same number means different things in each. They are exported as named constants from [`IBittyV1Guard.sol`](src/interfaces/IBittyV1Guard.sol) so consumers do not hardcode integers:

| Constant | Value | Namespace |
|----------|-------|-----------|
| `ASSET_STABLE_COIN` | `1` | Assets |
| `ASSET_CRYPTO` | `2` | Assets |
| `PROTOCOL_LENDING` | `1` | Protocols |
| `PROTOCOL_STAKING` | `2` | Protocols |
| `PROTOCOL_AMM` | `3` | Protocols |
| `PROTOCOL_INTENT` | `4` | Protocols |
| `IMPLEMENTATION_VAULT` | `1` | Implementations |
| `IMPLEMENTATION_SUB_VAULT` | `2` | Implementations |

Implementation categories are what keep a main vault from upgrading to sub-vault code, or the reverse — two contracts with incompatible storage layouts and authority models.

## Upgradeability

The guard is itself a UUPS proxy (`ERC1967Proxy` + `UUPSUpgradeable`). It has to be: vaults compile the guard address in as a constant, so that address can never move, but the registry's shape has changed once already (per-category implementations) and will again.

- `_authorizeUpgrade` is gated on `DEFAULT_ADMIN_ROLE` — the strictest role, not the operational ones.
- The implementation's constructor calls `_disableInitializers()`, so the logic contract cannot be initialized directly.
- `initialize` is `initializer`-guarded and additionally requires `tx.origin == DEPLOYER`, which stops anyone front-running initialization of a freshly deployed proxy.

## Access control

Administration uses OpenZeppelin `AccessControlDefaultAdminRules` with a **7-day delay** on `DEFAULT_ADMIN_ROLE` transfers.

| Role | Scope |
|------|-------|
| `DEFAULT_ADMIN_ROLE` | Role grants, contract upgrades |
| `ASSET_MANAGER_ROLE` | Asset registry |
| `PROTOCOL_MANAGER_ROLE` | Protocol registration / deprecation, all protocol categories |
| `IMPLEMENTATION_MANAGER_ROLE` | Implementation registry, all implementation categories |

One role per registry: what an account may **hold**, what it may **use**, and what it may **upgrade to**.

A holder of `PROTOCOL_MANAGER_ROLE` can register any protocol category. Per-category manager roles existed in an earlier design; if separate custody is needed again, that would mean restoring per-category roles rather than hiding checks inside the current ones.

`IMPLEMENTATION_MANAGER_ROLE` is kept **deliberately separate** from the asset/protocol roles because blessing an implementation is the highest-blast-radius privilege — every account of that category can upgrade to it, so a bad entry can drain them all. It is meant to be held by a governance `TimelockController`, giving upgrades a delay while asset/protocol management stays fast and operational. At deploy, `initialize` grants all three roles to `DEPLOYER` as a launch bootstrap (so it can register the first implementation before governance is stood up); the intended hand-off is to **revoke `IMPLEMENTATION_MANAGER_ROLE` from the deployer and grant it to the timelock** once governance is live. `DEFAULT_ADMIN_ROLE` can perform that grant/revoke at any time.

## Deployment

Two contracts are deployed, by two different factories, on purpose:

| Contract | Factory | Salt | Constructor args |
|----------|---------|------|------------------|
| `BittyV1Guard` (implementation) | Arachnid deterministic-deployment-proxy `0x4e59b44847b379578588920cA78FbF26c0B4956C` | `bytes32(0)` | none |
| `ERC1967Proxy` (the guard address) | [ImmutableCreate2Factory](https://github.com/ProjectOpenSea/seaport/blob/main/docs/ImmutableCreate2Factory.md) `0x0000000000FFe8B47B3e2130213B802212439497` | deployer-prefixed vanity salt | `(implementation, "")` |

The vanity salt is spent on the **proxy**, since that is the address vaults name. `ImmutableCreate2Factory` enforces that the salt's leading 20 bytes equal the caller, so only the designated deployer can land the contract at the target address. The implementation goes through the plain CREATE2 deployer at salt `0`, which makes its address a pure function of its init code.

Only `tx.origin == DEPLOYER` (`0x12EE2de7BF086388B1D560eb95e7191Edfab9823`) may initialize the proxy.

Both steps are idempotent — the scripts check for existing code before deploying, so a re-run of a partially finished deploy completes it rather than reverting.

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

The script logs the implementation address and the proxy init-code hash. Keep both — the first is what you verify, the second is what you mine a new vanity salt against if the implementation ever changes shape.

## Verifying the contract

Because the guard is a proxy, **two** contracts must be verified, and the proxy must additionally be linked to its implementation so explorers show the registry's real ABI. Verifying only one leaves the guard looking like an empty contract on Etherscan.

Foundry reads `foundry.toml` for the compiler settings, so the `0.8.34` / `optimizer_runs = 10000` / `via_ir = true` triple is matched automatically. Getting any of those wrong is the usual cause of a bytecode mismatch.

One Etherscan V2 API key covers every chain; `--chain` selects the explorer.

```shell
export ETHERSCAN_API_KEY=...
```

### 1. Find the implementation address

Read it out of the proxy's ERC-1967 slot rather than trusting a note — this is always the implementation actually in use:

```shell
cast storage 0x0000000008889521Db10f4c1eb20eF49179b498C \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  --rpc-url sepolia
```

The slot is `bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`. The value is left-padded; the last 20 bytes are the address.

### 2. Verify the implementation

No constructor arguments:

```shell
forge verify-contract \
  --chain sepolia \
  --watch \
  <IMPLEMENTATION_ADDRESS> \
  src/BittyV1Guard.sol:BittyV1Guard
```

### 3. Verify the proxy

`ERC1967Proxy` comes from the OpenZeppelin submodule, so give its path inside `lib/`, and pass the constructor arguments it was deployed with — the implementation address and **empty** init data, since `initialize` is called in a separate transaction:

```shell
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <IMPLEMENTATION_ADDRESS> 0x) \
  0x0000000008889521Db10f4c1eb20eF49179b498C \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
```

If the constructor arguments are wrong the verification fails with a bytecode mismatch, because they are appended to the deployed init code.

### 4. Link the proxy to its implementation

Verification alone does not make Etherscan render the guard's functions — the proxy's own ABI has none. Mark it as a proxy so the Read/Write tabs show the implementation's interface:

```shell
curl -X POST "https://api.etherscan.io/v2/api?chainid=11155111" \
  -d "module=contract" \
  -d "action=verifyproxycontract" \
  -d "apikey=$ETHERSCAN_API_KEY" \
  -d "address=0x0000000008889521Db10f4c1eb20eF49179b498C" \
  -d "expectedimplementation=<IMPLEMENTATION_ADDRESS>"
```

The same thing is available in the UI under *Contract → More Options → Is this a proxy?*. This must be redone after every upgrade, since the implementation changes.

### Other chains

Swap `--chain sepolia` for `mainnet` or `base`, and the `chainid` above for `1` or `8453`:

```shell
forge verify-contract --chain mainnet --watch <IMPL> src/BittyV1Guard.sol:BittyV1Guard
forge verify-contract --chain base    --watch <IMPL> src/BittyV1Guard.sol:BittyV1Guard
```

### Verifying at deploy time

Adding `--verify` to the deploy command verifies both contracts as they are broadcast, which avoids step 1 entirely. It does **not** perform step 4:

```shell
forge script script/BittyV1GuardSepolia.s.sol:Deploy --broadcast --verify -vvvv
```

### Checking it worked

```shell
# Should print the compiler-settings-matched source, not "Contract source code not verified"
cast source <IMPLEMENTATION_ADDRESS> --chain sepolia

# Should answer through the proxy once linked
cast call 0x0000000008889521Db10f4c1eb20eF49179b498C \
  "isAssetRegistered(address)(bool)" 0x1c7d4b196cb0c7b01d743fbc6116a902379c7238 \
  --rpc-url sepolia
```

### After an upgrade

An upgrade replaces the implementation but keeps the proxy address, so repeat steps **1, 2 and 4** — the proxy itself stays verified and does not need re-verifying.

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
// One-time setup, called on the proxy after deployment
function initialize(
    address[] calldata assets,
    uint8[] calldata assetCategories,
    address[] calldata protocols,
    uint8[] calldata protocolCategories
) external;

// Assets — every asset carries a category; stable coins use ASSET_STABLE_COIN
function addAssets(address[] calldata, uint8[] calldata categories) external;
function removeAssets(address[] calldata) external;
function isAssetRegistered(address) external view returns (bool);
function assetCategory(address) external view returns (uint8);

// Protocols — enumerable, split into active and deprecated
function addProtocols(address[] calldata, uint8[] calldata categories) external;
function deprecateProtocols(address[] calldata) external;
function isProtocolRegistered(address) external view returns (bool);
function isProtocolDeprecated(address) external view returns (bool);
function protocolCategory(address) external view returns (uint8);
function getProtocols() external view returns (address[] memory);
function getDeprecatedProtocols() external view returns (address[] memory);

// Implementations — per category, one current plus a set of accepted past ones
function setImplementation(address implementation, uint8 category) external;
function retireImplementations(address[] calldata implementations, uint8 category) external;
function isImplementationRegisteredFor(address implementation, uint8 category) external view returns (bool);
function latestImplementation(uint8 category) external view returns (address);
function getPastImplementations(uint8 category) external view returns (address[] memory);

// Events
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
| `NotDeployer()` | `initialize` called with `tx.origin != DEPLOYER` |
| `LengthMismatch()` | Address and category arrays differ in length |
| `NotRegisteredProtocol(address)` | `deprecateProtocols` targets an address that is not registered |
| `NotRegisteredImplementation(address)` | `retireImplementations` targets an address that is not a past implementation of that category |
| `AddressZero()` | `setImplementation` given a zero implementation or a zero category |

### Design notes

**What is enumerable, and why.** Protocols and past implementations are `EnumerableSet`s and can be listed; assets are a plain mapping and cannot. That asymmetry is deliberate: a vault has to answer "does this NFT belong to some protocol?", which no membership test can settle, so it needs the full protocol list. Nothing asks an equivalent question of assets, so they stay a single `SLOAD` with no iteration cost. Consumers needing the full asset set replay `AssetAdded` / `AssetRemoved` from the deployment block; events fire only on real state changes, so a replay never double-counts.

**Re-adding.** Registering an asset or protocol already active with the same category is a no-op (no event). Re-registering a deprecated protocol clears its deprecation flag and returns it to the active set.

**Stable coins.** There is no `isStableCoinRegistered` — check `isAssetRegistered(token) && assetCategory(token) == ASSET_STABLE_COIN`.

**Implementations.** Each category holds one `latestImplementation` plus a set of past ones. `setImplementation` promotes the incoming address and demotes the outgoing one into that set, so accounts that have not yet upgraded stay valid — `isImplementationRegisteredFor` accepts current *or* past. `retireImplementations` removes entries from the past set, which forces those accounts to upgrade before they can upgrade again; it cannot remove the current implementation, and it reverts on an address that was never there rather than passing silently. The registry carries no timelock of its own — the review delay is enforced by the governance `TimelockController` holding `IMPLEMENTATION_MANAGER_ROLE`.

See [`IBittyV1Guard.sol`](src/interfaces/IBittyV1Guard.sol) for full NatSpec.

## Project layout

```
src/
  BittyV1Guard.sol          # Registry contract (UUPS implementation)
  interfaces/
    IBittyV1Guard.sol       # Public interface, errors, category constants
script/
  BaseDeploy.sol            # Shared deploy harness (TOML config, address persistence)
  BittyV1GuardMainnet.s.sol
  BittyV1GuardBase.s.sol
  BittyV1GuardSepolia.s.sol
deployments/
  mainnet.toml              # Chain-specific token addresses + deployed guard address
  base.toml
  sepolia.toml
test/
  local/BittyV1Guard.t.sol  # Unit tests — asset / protocol / implementation registries
```

## License

AGPL-3.0-only
