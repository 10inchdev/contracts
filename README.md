# AsterPad Smart Contracts

[![Smart Contract Tests](https://github.com/10inchdev/contracts/actions/workflows/test.yml/badge.svg)](https://github.com/10inchdev/contracts/actions/workflows/test.yml)

BSC Token Launchpad with Snowball/Fireball auto-buyback mechanics and perpetual creator fees.

## Contracts

| Contract | Description |
|----------|-------------|
| **PredictionMarketV1.sol** | 🆕 UUPS Upgradeable prediction markets for token milestones |
| **TokenFactoryV2Optimized.sol** | 🆕 UUPS Upgradeable factory with creator auto-exempt fix |
| **SnowballFactoryV3Flattened.sol** | 🆕 UUPS Upgradeable Snowball/Fireball wrapper V3 |
| **AsterPadRouterFlattened.sol** | Perpetual fee router for post-graduation trading |
| **AsterPadV2Optimized.sol** | Main factory contract (Standard mode) |
| **SnowballFactoryV2Flattened.sol** | Snowball/Fireball wrapper V2 (deprecated) |
| **SnowballFactoryFlattened.sol** | Snowball/Fireball wrapper V1 (deprecated) |

## Features

### 🆕 Prediction Markets (December 2024)

Binary prediction markets for AsterPad tokens - bet YES/NO on token milestones:

- **Market Cap Targets**: "Will $RIZZ hit $100K mcap?"
- **Graduation**: "Will $MPEPE graduate this week?"
- **Price Targets**: "Will $DAWG reach $0.001?"
- **Volume Targets**: "Will $PLANKTON hit 100 BNB volume?"

**Features:**
- Token creators create predictions **FREE**
- Others pay 0.05 BNB creation fee
- Chainlink BNB/USD oracle for price verification
- 2% platform fee on winnings
- Permissionless resolution (anyone can call after deadline)
- ReentrancyGuard, Pausable, 2-step ownership
- 48-hour upgrade timelock for security
- Flash loan & slippage protection
- UUPS Upgradeable

### 🆕 V3 Upgradeable Contracts (December 2024)

Both `TokenFactoryV2` and `SnowballFactoryV3` use the **UUPS Proxy Pattern** for upgradeability:

- **Future-proof**: Can fix bugs and add features without redeploying
- **Same address forever**: Users always interact with the proxy address
- **Admin controlled**: Only owner can authorize upgrades

#### TokenFactoryV2 Improvements
- **Creator Auto-Exempt**: Tokens automatically exempt their creator from trading restrictions
- **Fixes Snowball Bug**: SnowballFactory can now transfer tokens to DEAD address for burning
- **Optimized Size**: Under 24KB deployment limit

#### SnowballFactoryV3 Improvements
- **Configurable Threshold**: `minBuybackThreshold` adjustable by admin (0.001 - 1 BNB)
- **Per-Pool Tracking**: Fair distribution of buybacks per token
- **UUPS Upgradeable**: Can be upgraded for future improvements

### AsterPadRouter - Perpetual Creator Fees

After tokens graduate from the bonding curve to PancakeSwap, trades go through the AsterPadRouter to maintain fee collection:

- **Platform Fee**: 1.0% (goes to treasury)
- **Creator Fee**: 0.5% (perpetual royalties to token creator)
- **Total**: 1.5% on all post-graduation trades

**Key Features:**
- OpenZeppelin security (ReentrancyGuard, Pausable, Ownable2Step)
- Supports Standard, Snowball, and Fireball launch modes
- Auto-buyback for Snowball/Fireball tokens
- Batch registration for existing graduated tokens
- Per-token statistics tracking

### Snowball/Fireball Launch Modes

- **Snowball ❄️** - Creator's 0.5% fee goes to auto-buyback + burn
- **Fireball 🔥** - Same as Snowball (different branding)

### How It Works

1. Creator launches token with Snowball/Fireball mode via `SnowballFactoryV3`
2. Trading fees (0.5% creator fee) accumulate in the contract **per token**
3. When threshold is met (0.01 BNB default), fees are used to buy back tokens
4. Bought tokens are burned (sent to 0x...dEaD)
5. Result: Deflationary pressure, increasing token value

## Deployed Contracts (BSC Mainnet)

### Prediction Markets v1.2.2 (December 2024 - UUPS Upgradeable)

| Contract | Type | Address | Verified |
|----------|------|---------|----------|
| PredictionMarketV1 | **Proxy (MAIN)** | [`0xD55Cfc363bd4d22afa56Fef78486c145c15b3e4b`](https://bscscan.com/address/0xD55Cfc363bd4d22afa56Fef78486c145c15b3e4b) | ⏳ |
| PredictionMarketV1 | Implementation v1.2.2 | [`0x5840cc98a85C54bae8474BFE048F03Bb0F003488`](https://bscscan.com/address/0x5840cc98a85C54bae8474BFE048F03Bb0F003488) | ⏳ |

**Features in v1.2.2:**
- ✅ Fixed claim reentrancy bug
- ✅ 48-hour upgrade timelock
- ✅ Flash loan protection (same-block bet/claim prevention)
- ✅ Slippage protection for claims
- ✅ Permissionless resolution (anyone can resolve after deadline)

**Deprecated (PAUSED):**
| Contract | Address | Status |
|----------|---------|--------|
| Old Proxy v1.2.1 | `0xE71F0961d5738dA23874f218Cf26051f4AD0CfC4` | ⚠️ PAUSED |

### V3 Contracts (Current - UUPS Upgradeable)

| Contract | Type | Address | Verified |
|----------|------|---------|----------|
| TokenFactoryV2 | Proxy | [`0xd2889580D9C8508696c9Ce82149E8867632E6C76`](https://bscscan.com/address/0xd2889580D9C8508696c9Ce82149E8867632E6C76) | ✅ |
| TokenFactoryV2 | Implementation | [`0x07C6a591C4bDF892a9d7F1d03A418a9c321B0482`](https://bscscan.com/address/0x07C6a591C4bDF892a9d7F1d03A418a9c321B0482) | ✅ |
| SnowballFactoryV3 | Proxy | [`0x06587986799224a88b8336f6ae0bb1d84ba6c026`](https://bscscan.com/address/0x06587986799224a88b8336f6ae0bb1d84ba6c026) | ✅ |
| SnowballFactoryV3 | Implementation | [`0x60259109578d148210f155f6ca907435ee750115`](https://bscscan.com/address/0x60259109578d148210f155f6ca907435ee750115) | ✅ |

### V1/V2 Contracts (Legacy)

| Contract | Address | Verified |
|----------|---------|----------|
| TokenFactory (Main) | [`0x0fff767cad811554994f3b9e6317730ff25720e3`](https://bscscan.com/address/0x0fff767cad811554994f3b9e6317730ff25720e3) | ✅ |
| SnowballFactoryV2 | [`0x9DF2285dB7c3dd16DC54e97607342B24f3037Cc5`](https://bscscan.com/address/0x9DF2285dB7c3dd16DC54e97607342B24f3037Cc5) | ✅ |
| AsterPadRouter | [`0x20302F780d8b3b0fC96d8cB56C528F29ae8F7a28`](https://bscscan.com/address/0x20302F780d8b3b0fC96d8cB56C528F29ae8F7a28) | ✅ |

## Running Tests

```bash
# Install dependencies
npm install

# Compile contracts
npm run compile

# Run all tests
npm test

# Run prediction market tests (38 tests)
npx hardhat test test/PredictionMarketV1.test.ts

# Run with coverage
npm run coverage
```

## Test Coverage

### PredictionMarketV1 (38 tests)
- ✅ Initialization (owner, version, fee recipient)
- ✅ Create prediction (free for creators, fee for others)
- ✅ Betting (YES/NO, limits, freeze period, same side only)
- ✅ Resolution (market cap, graduation, price target, volume)
- ✅ Claiming winnings (2% fee calculation)
- ✅ Admin functions (pause, 2-step ownership, emergency resolve)
- ✅ Oracle validation (staleness check, zero price)
- ✅ View functions

### AsterPadRouter (51 tests)
- ✅ Deployment & initialization
- ✅ Token registration (Standard, Snowball, Fireball)
- ✅ Batch registration
- ✅ Buy tokens with fee extraction
- ✅ Sell tokens with fee extraction
- ✅ Snowball mode (fee accumulation for buyback)
- ✅ Execute buyback
- ✅ Admin functions (pause, treasury, creator update)
- ✅ Ownable2Step (two-step ownership transfer)
- ✅ Reentrancy protection
- ✅ View functions

### SnowballFactoryV2 (40 tests)
- ✅ Deployment & initialization
- ✅ Token creation (Snowball & Fireball modes)
- ✅ Per-pool tracking (V2)
- ✅ Access control (Ownable2Step, Pausable)
- ✅ Admin functions
- ✅ BNB recovery
- ✅ Buyback functions
- ✅ Multiple token creation
- ✅ Global stats

## Security

All contracts use OpenZeppelin security patterns:
- `ReentrancyGuard` - Prevents reentrancy attacks
- `Pausable` - Emergency pause functionality
- `Ownable2Step` - Two-step ownership transfer (prevents accidental transfers)
- `SafeERC20` - Safe token transfers
- `UUPSUpgradeable` - Secure upgrade mechanism (V3 contracts)

## Admin Functions (V3)

**Owner:** `0x3717E1A8E2788Ac53D2D5084Dc6FF93d03369D27`

| Function | Description |
|----------|-------------|
| `setMinBuybackThreshold(uint256)` | Adjust buyback threshold (0.001 - 1 BNB) |
| `setTokenFactory(address)` | Update TokenFactory address |
| `pause()` / `unpause()` | Emergency pause |
| `emergencyWithdraw(address)` | Withdraw BNB (when paused) |
| `upgradeTo(address)` | Upgrade to new implementation |

## License

MIT
