# Bitty Guard

On-chain registry of allowed assets, DeFi protocols, and account implementations for [Bitty](https://github.com/BittyIO) vaults. The guard is the source of truth for what tokens vaults may hold, which external protocols they may interact with, and which implementations they may upgrade to.

| Chain   | Address |
|---------|---------|
| Mainnet | [`0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00`](https://etherscan.io/address/0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00) |
| Base    | [`0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00`](https://basescan.org/address/0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00) |
| Sepolia | [`0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00`](https://sepolia.etherscan.io/address/0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00) |

One address on every chain. Live on Sepolia; Mainnet and Base are not deployed yet and will land here when they are.

**This is not a coincidence to be maintained by hand.** The proxy is born on a constant bootstrap implementation rather than on the current build (see [Deployment](#deployment)), so its init code — and therefore its CREATE2 address — is identical everywhere, at every version. A new chain reaches it by running the deploy script, with nothing to reproduce from an older commit.

This is a **proxy** address. The guard is a UUPS proxy, so the address above is what vaults compile in and never changes; the implementation behind it does.

## Overview

`BittyV1Guard` maintains three registries:

| Registry | Lifecycle | Effect |
|----------|-----------|--------|
| **Assets** | Add / remove | Removed assets can only be sold, not bought |
| **Protocols** | Add / deprecate | Deprecated protocols are exit-only — existing positions can be withdrawn, but no new deposits |
| **Implementations** | Set / retire | An account may only UUPS-upgrade to the current or a past implementation of its category; retiring one blocks it as a *future* target but does not affect accounts already running it |

There is no separate stable-coin registry. A stable coin is an asset whose category bitmask includes `ASSET_STABLE_COIN`; callers distinguish token types with a bitwise test — `assetCategory(token) & ASSET_STABLE_COIN != 0` — not `==` (see the asset-bitmask note under [Category conventions](#category-conventions)).

The implementation registry is what makes account upgrades governance-gated: each account's `_authorizeUpgrade` asks `isImplementationRegisteredFor(newImpl, category)`, so no account can upgrade to code the guard has not blessed. Registration here is immediate — the upgrade **delay** lives in governance (the `IMPLEMENTATION_MANAGER_ROLE` holder is a `TimelockController`), not in this contract.

Every registry entry carries a `uint8` category supplied by the caller. The guard rejects category `0` (treated as "skip this entry" for assets and protocols, and as an error for implementations) and does not interpret any other value — meaning is a convention shared with vaults and other consumers. Category `0` on read means the address was never registered. Because the value is stored verbatim and never interpreted, **assets treat it as a bitmask** (one asset can hold several categories at once, below); protocols and implementations use it as a single category.

### Category conventions

The three category namespaces are independent — the same number means different things in each. The shipped constants are exported from [`IBittyV1Guard.sol`](src/interfaces/IBittyV1Guard.sol) so consumers do not hardcode integers; `ASSET_AMM_SUPPORTED` is **reserved by convention here** (the guard already stores it fine as an opaque bitmask value — see below — so it is documented now and added to the interface when a consumer adopts it):

| Constant | Value | Namespace | Kind |
|----------|-------|-----------|------|
| `ASSET_STABLE_COIN` | `1` (`0b0001`) | Assets | bit flag |
| `ASSET_CRYPTO` | `2` (`0b0010`) | Assets | bit flag |
| `ASSET_AMM_SUPPORTED` | `4` (`0b0100`) | Assets | bit flag |
| `PROTOCOL_LENDING` | `1` | Protocols | single value |
| `PROTOCOL_STAKING` | `2` | Protocols | single value |
| `PROTOCOL_AMM` | `3` | Protocols | single value |
| `PROTOCOL_INTENT` | `4` | Protocols | single value |
| `IMPLEMENTATION_VAULT` | `1` | Implementations | single value |

**Asset categories are a bitmask.** Every `ASSET_*` flag is a distinct power of two, so an asset's `assetCategory` is the OR of *every* category it belongs to — one asset can be several at once. Register an asset with the combined mask, and test membership with a bitwise AND, never `==`:

```solidity
// ETH is both crypto AND usable in AMM pools:
addAssets([WETH], [ASSET_CRYPTO | ASSET_AMM_SUPPORTED]);   // stores 2 | 4 = 6

// Consumers check a single capability, ignoring the other bits:
guard.assetCategory(WETH) & ASSET_STABLE_COIN   != 0;      // false
guard.assetCategory(WETH) & ASSET_AMM_SUPPORTED != 0;      // true
```

An `==` comparison (`assetCategory(token) == ASSET_STABLE_COIN`) is a bug the moment an asset carries more than one flag — always mask with `&`.

Adding a new asset capability is just the next power of two (`8`, `16`, …). The guard needs no change — it stores the mask verbatim and never interprets it — so a new flag is only a convention agreed with consumers plus its constant here and in `IBittyV1Guard.sol`. `ASSET_AMM_SUPPORTED` above is documented as that convention; keep the values powers of two so they stay OR-able.

Protocol and implementation categories are **not** bitmasks — each entry is exactly one category (a protocol is one kind of protocol; an implementation belongs to one account type), so those are read with `==`.

Sub vaults have no category of their own. A sub vault is a beacon proxy whose beacon is its parent vault, so it runs the sub-vault build shipped with the parent's own — already guard-blessed — implementation, and follows the parent's upgrade automatically. There is nothing separate for the guard to bless. The registry itself stays generic over `category`, so a future account type can claim `2` without a contract change.

## Upgradeability

The guard is itself a UUPS proxy (`ERC1967Proxy` + `UUPSUpgradeable`). It has to be: vaults compile the guard address in as a constant, so that address can never move, but the registry's shape has changed once already (per-category implementations) and will again.

- `_authorizeUpgrade` is gated on `DEFAULT_ADMIN_ROLE` — the strictest role, not the operational ones.
- The implementation's constructor calls `_disableInitializers()`, so the logic contract cannot be initialized directly.
- `initialize` is `initializer`-guarded and additionally requires `tx.origin == DEPLOYER`, which stops anyone front-running initialization of a freshly deployed proxy.
- `guardVersion()` and `versionName()` report the build behind the proxy (`1.0.0`), encoded `major * 1e6 + minor * 1e3 + patch`. Reading it back is the cheapest confirmation that an upgrade actually landed.

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

Three contracts are deployed, by two different factories, on purpose:

| Contract | Factory | Salt | Constructor args |
|----------|---------|------|------------------|
| `BittyV1GuardBootstrap` | Arachnid deterministic-deployment-proxy `0x4e59b44847b379578588920cA78FbF26c0B4956C` | `bytes32(0)` | none |
| `BittyV1Guard` (implementation) | same | `bytes32(0)` | none |
| `ERC1967Proxy` (the guard address) | [ImmutableCreate2Factory](https://github.com/ProjectOpenSea/seaport/blob/main/docs/ImmutableCreate2Factory.md) `0x0000000000FFe8B47B3e2130213B802212439497` | deployer-prefixed vanity salt | `(bootstrap, "")` |

The vanity salt is spent on the **proxy**, since that is the address vaults name. `ImmutableCreate2Factory` enforces that the salt's leading 20 bytes equal the caller, so only the designated deployer can land the contract at the target address. The other two go through the plain CREATE2 deployer at salt `0`, which makes each address a pure function of its init code.

**The proxy is born on the bootstrap, not on the build.** A proxy's init code embeds its implementation, so a proxy pointed straight at `BittyV1Guard` would move to a new address on every guard release — and a second chain could only match the first by rebuilding the exact implementation that chain was born with, from the commit that produced it, forever. `BittyV1GuardBootstrap` is a permanent do-nothing implementation that takes the build out of the hash; the deploy script upgrades the proxy to the real `BittyV1Guard` in the same run. Its `_authorizeUpgrade` is gated on `tx.origin == DEPLOYER`, because the proxy address is reproducible on every chain and the window before the first upgrade would otherwise be open to anyone on a chain Bitty has not reached yet.

The consequence to remember: **the proxy's constructor argument is the bootstrap address and stays that way forever**, including when verifying after an upgrade. It is never the current implementation.

Only `tx.origin == DEPLOYER` (`0x12EE2de7BF086388B1D560eb95e7191Edfab9823`) may initialize the proxy.

Every step is idempotent — create, upgrade and initialize are each skipped once done, so a re-run of a partially finished deploy completes it rather than reverting, and a re-run of a finished one reports that there is nothing left to do.

The deploy itself lives in `script/DeployGuard.sol`, shared by the three chain scripts; a chain script states only which assets and protocols to register. The salt, the bootstrap and the factory address are deliberately in the shared file — three copies of the value that fixes a single cross-chain address is exactly what drifts.

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

Because the guard is a proxy, **three** contracts must be verified — the proxy, the implementation behind it, and the bootstrap it was born on — and the proxy must additionally be linked to its implementation so explorers show the registry's real ABI. Verifying only the proxy leaves the guard looking like an empty contract on Etherscan.

Foundry reads `foundry.toml` for the compiler settings, so the `0.8.34` / `optimizer_runs = 10000` / `via_ir = true` triple is matched automatically. Getting any of those wrong is the usual cause of a bytecode mismatch.

One Etherscan V2 API key covers every chain; `--chain` selects the explorer.

```shell
export ETHERSCAN_API_KEY=...
```

### 1. Find the implementation address

Read it out of the proxy's ERC-1967 slot rather than trusting a note — this is always the implementation actually in use:

```shell
cast storage 0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00 \
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

### 3. Verify the bootstrap

No constructor arguments:

```shell
forge verify-contract \
  --chain sepolia \
  --watch \
  0xCb43DEd835f57Be1732A320a8F26c78595cF609A \
  src/BittyV1GuardBootstrap.sol:BittyV1GuardBootstrap
```

### 4. Verify the proxy

`ERC1967Proxy` comes from the OpenZeppelin submodule, so give its path inside `lib/`, and pass the constructor arguments it was deployed with — the **bootstrap** address and **empty** init data, since `initialize` is called in a separate transaction:

```shell
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" 0xCb43DEd835f57Be1732A320a8F26c78595cF609A 0x) \
  0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
```

Note the argument is the **bootstrap**, not the implementation from step 1. Passing the implementation is the natural mistake and fails with a bytecode mismatch, because constructor arguments are appended to the deployed init code. It stays the bootstrap after every upgrade.

### 5. Link the proxy to its implementation

Verification alone does not make Etherscan render the guard's functions — the proxy's own ABI has none. Mark it as a proxy so the Read/Write tabs show the implementation's interface:

```shell
curl -X POST "https://api.etherscan.io/v2/api?chainid=11155111" \
  -d "module=contract" \
  -d "action=verifyproxycontract" \
  -d "apikey=$ETHERSCAN_API_KEY" \
  -d "address=0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00" \
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

Adding `--verify` to the deploy command verifies the contracts as they are broadcast, which avoids step 1 entirely. It does **not** perform step 5:

```shell
forge script script/BittyV1GuardSepolia.s.sol:Deploy --broadcast --verify -vvvv
```

### Checking it worked

```shell
# Should print the compiler-settings-matched source, not "Contract source code not verified"
cast source <IMPLEMENTATION_ADDRESS> --chain sepolia

# Should answer through the proxy once linked
cast call 0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00 \
  "isAssetRegistered(address)(bool)" 0x1c7d4b196cb0c7b01d743fbc6116a902379c7238 \
  --rpc-url sepolia

# Should report the build actually running behind the proxy
cast call 0x9FFd004eDd0eBE0F5B0000c0002e0200001d8D00 "versionName()(string)" --rpc-url sepolia
```

### After an upgrade

An upgrade replaces the implementation but keeps the proxy address, so repeat steps **1, 2 and 5** — the proxy and the bootstrap stay verified and do not need re-verifying. The proxy's constructor argument never changes, because it names the bootstrap rather than the build.

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
// Version of the build behind the proxy, encoded major * 1e6 + minor * 1e3 + patch
function guardVersion() external pure returns (uint256);
function versionName() external pure returns (string memory);

// One-time setup, called on the proxy after deployment
function initialize(
    address[] calldata assets,
    uint8[] calldata assetCategories,
    address[] calldata protocols,
    uint8[] calldata protocolCategories
) external;

// Assets — each `category` is a BITMASK (OR of ASSET_* flags); test with `& flag != 0`, not `==`
function addAssets(address[] calldata, uint8[] calldata categories) external;
function removeAssets(address[] calldata) external;
function isAssetRegistered(address) external view returns (bool);
function assetCategory(address) external view returns (uint8); // the full bitmask

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
| `NotDeployer()` | `initialize` called with `tx.origin != DEPLOYER`, or an upgrade off `BittyV1GuardBootstrap` attempted by anyone else |
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
  BittyV1GuardBootstrap.sol # Constant implementation the proxy is born on; fixes the guard address
  interfaces/
    IBittyV1Guard.sol       # Public interface, errors, category constants
script/
  BaseDeploy.sol            # Shared deploy harness (TOML config, address persistence, CREATE2)
  DeployGuard.sol           # The deploy itself: salt, bootstrap, proxy, upgrade, initialize
  BittyV1GuardMainnet.s.sol # Per chain: which assets and protocols to register, nothing else
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
