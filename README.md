# Bitty Guard

On-chain registry of allowed assets and DeFi protocols for [Bitty](https://github.com/BittyIO) vaults. The guard is the source of truth for what tokens vaults may hold and which external protocols they may interact with.

Deployed at the same address on every supported chain via CREATE2:

| Chain   | Address |
|---------|---------|
| Mainnet | [`0x00D4000023b177003fb1bF1d3160BaefF5c60000`](https://etherscan.io/address/0x00D4000023b177003fb1bF1d3160BaefF5c60000) |
| Base    | [`0x00D4000023b177003fb1bF1d3160BaefF5c60000`](https://basescan.org/address/0x00D4000023b177003fb1bF1d3160BaefF5c60000) |
| Sepolia | [`0x00D4000023b177003fb1bF1d3160BaefF5c60000`](https://sepolia.etherscan.io/address/0x00D4000023b177003fb1bF1d3160BaefF5c60000) |

## Overview

`BittyV1Guard` maintains three registries:

| Registry | Lifecycle | Effect |
|----------|-----------|--------|
| **Assets** | Add / remove | Removed assets can only be sold, not bought |
| **Stable coins** | Add / remove | Removed stable coins can only be sold, not bought |
| **Protocols** | Add / deprecate | Deprecated protocols are exit-only — existing positions can be withdrawn, but no new deposits |

Protocol categories are not passed in by the caller. Each protocol declares exactly one Bitty category via [ERC-165](https://eips.ethereum.org/EIPS/eip-165) at registration time; the guard records that declaration in `protocolCategory` and enforces the matching manager role. A protocol that declares zero or more than one category is rejected.

### Protocol categories

| Category | Interface ID | Manager role | Deprecated behavior |
|----------|--------------|--------------|---------------------|
| Lending | `0xb9f16a0c` | `LENDING_MANAGER_ROLE` | Withdraw-only |
| Staking | `0xc8ada217` | `STAKING_MANAGER_ROLE` | Unstake-only |
| AMM | `0x932722bd` | `AMM_MANAGER_ROLE` | Remove LP only |
| Intent | `0x1626ba7e` | `INTENT_MANAGER_ROLE` | Cancel trades only |

Interface IDs are pinned here and in [protocol-store](https://github.com/BittyIO/protocol-store) (`InterfaceIds.t.sol`). Change them in both repos together.

## Access control

Administration uses OpenZeppelin `AccessControlDefaultAdminRules` with a 7-day delay on `DEFAULT_ADMIN_ROLE` transfers.

| Role | Scope |
|------|-------|
| `DEFAULT_ADMIN_ROLE` | Role grants, initialization |
| `ASSET_MANAGER_ROLE` | Asset registry |
| `STABLE_COIN_MANAGER_ROLE` | Stable coin registry |
| `LENDING_MANAGER_ROLE` | Lending protocol registration / deprecation |
| `STAKING_MANAGER_ROLE` | Staking protocol registration / deprecation |
| `AMM_MANAGER_ROLE` | AMM protocol registration / deprecation |
| `INTENT_MANAGER_ROLE` | Intent protocol registration / deprecation |

Each category has its own manager so operations can be split across addresses. `addProtocols` checks the caller holds the role for each protocol's declared category; a batch spanning multiple categories requires every relevant role.

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
// Assets & stable coins
function addAssets(address[] calldata) external;
function removeAssets(address[] calldata) external;
function isAssetRegistered(address) external view returns (bool);

function addStableCoins(address[] calldata) external;
function removeStableCoins(address[] calldata) external;
function isStableCoinRegistered(address) external view returns (bool);

// Protocols — category is discovered via ERC-165, not supplied by caller
function addProtocols(address[] calldata) external;
function deprecateProtocols(address[] calldata) external;
function isProtocolRegistered(address) external view returns (bool);
function isProtocolDeprecated(address) external view returns (bool);
function protocolCategory(address) external view returns (bytes4);

// Bulk reads
function getAssets() external view returns (address[] memory);
function getStableCoins() external view returns (address[] memory);
function getProtocols() external view returns (address[] memory); // active only
```

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
  local/BittyV1Guard.t.sol  # Unit tests
```

## License

AGPL-3.0-only
