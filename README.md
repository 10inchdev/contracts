# AsterPad Smart Contracts

[![Smart Contract Tests](https://github.com/10inchdev/contracts/actions/workflows/test.yml/badge.svg)](https://github.com/10inchdev/contracts/actions/workflows/test.yml)

BSC Token Launchpad with Snowball/Fireball auto-buyback mechanics.

## Contracts

| Contract | Description |
|----------|-------------|
| **AsterPadV2Optimized.sol** | Main factory contract (deployed on BSC Mainnet) |
| **TokenFactory.sol** | Token creation factory |
| **SnowballFactoryV2Flattened.sol** | Snowball/Fireball wrapper V2 (per-pool fair distribution) |
| **SnowballFactoryFlattened.sol** | Snowball/Fireball wrapper V1 (deprecated) |

## Features

### Snowball/Fireball Launch Modes
- **Snowball 🎿** - 50% of creator fees auto-buyback + burn
- **Fireball 🔥** - 50% of creator fees auto-buyback + burn (same mechanics, different branding)

### How It Works
1. Creator launches token with Snowball/Fireball mode
2. Trading fees (0.5% creator fee) accumulate in the wrapper contract **per pool**
3. When threshold is met (0.001 BNB default), fees are used to buy back tokens from that specific pool
4. Bought tokens are burned (sent to 0x...dEaD)
5. Result: Deflationary pressure, increasing token value

### V2 Improvements
- **Fair Per-Pool Distribution**: Each token's creator fees only buy back THAT token
- **Batch Processing**: `batchAutoBuyback()` for efficient cron processing
- **Configurable Thresholds**: `minBuybackThreshold` and `minBuybackTokens`
- **Pool Query**: `getPoolsWithPendingBuybacks()` for automation

## Deployed Contracts (BSC Mainnet)

| Contract | Address | Verified |
|----------|---------|----------|
| TokenFactory (Main) | [`0x0fff767cad811554994f3b9e6317730ff25720e3`](https://bscscan.com/address/0x0fff767cad811554994f3b9e6317730ff25720e3) | ✅ |
| SnowballFactoryV2 | [`0x9DF2285dB7c3dd16DC54e97607342B24f3037Cc5`](https://bscscan.com/address/0x9DF2285dB7c3dd16DC54e97607342B24f3037Cc5) | ✅ |

## Running Tests

```bash
# Install dependencies
npm install

# Compile contracts
npm run compile

# Run tests (40 tests)
npm test

# Run with coverage
npm run coverage
```

## Test Coverage

- ✅ Deployment & initialization
- ✅ Token creation (Snowball & Fireball modes)
- ✅ Per-pool tracking (V2)
- ✅ Access control (Ownable2Step, Pausable)
- ✅ Admin functions
- ✅ BNB recovery
- ✅ Buyback functions
- ✅ Multiple token creation
- ✅ Global stats

## License

MIT
