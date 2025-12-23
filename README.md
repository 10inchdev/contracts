# AsterPad Smart Contracts

[![Smart Contract Tests](https://github.com/10inchdev/contracts/actions/workflows/test.yml/badge.svg)](https://github.com/10inchdev/contracts/actions/workflows/test.yml)

BSC Token Launchpad with Snowball/Fireball auto-buyback mechanics and perpetual creator fees.

## Contracts

| Contract | Description |
|----------|-------------|
| **AsterPadRouterFlattened.sol** | 🆕 Perpetual fee router for post-graduation trading |
| **AsterPadV2Optimized.sol** | Main factory contract (deployed on BSC Mainnet) |
| **TokenFactory.sol** | Token creation factory |
| **SnowballFactoryV2Flattened.sol** | Snowball/Fireball wrapper V2 (per-pool fair distribution) |
| **SnowballFactoryFlattened.sol** | Snowball/Fireball wrapper V1 (deprecated) |

## Features

### 🆕 AsterPadRouter - Perpetual Creator Fees

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

- **Snowball 🎿** - Creator's 0.5% fee goes to auto-buyback + burn
- **Fireball 🔥** - Same as Snowball (different branding)

### How It Works

1. Creator launches token with Snowball/Fireball mode
2. Trading fees (0.5% creator fee) accumulate in the router contract **per token**
3. When threshold is met (0.001 BNB default), fees are used to buy back tokens
4. Bought tokens are burned (sent to 0x...dEaD)
5. Result: Deflationary pressure, increasing token value

### V2 Improvements

- **Fair Per-Pool Distribution**: Each token's creator fees only buy back THAT token
- **Batch Processing**: `batchExecuteBuyback()` for efficient cron processing
- **Configurable Thresholds**: `minBuybackThreshold`
- **Token Query**: `getTokensWithPendingBuybacks()` for automation

## Deployed Contracts (BSC Mainnet)

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

# Run all tests (91 tests)
npm test

# Run with coverage
npm run coverage
```

## Test Coverage

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

## License

MIT
