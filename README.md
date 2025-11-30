# 🏦 VaultForge

Multi-token savings bank with tiered interest rates and yield generation.

## Features

- ✅ Multi-token support
- ✅ Tiered lock periods (0d, 30d, 90d, 180d)
- ✅ Automated yield routing
- ✅ Referral system
- ✅ Early withdrawal penalties
- ✅ Protocol fee mechanism

## Architecture

[Diagram to be added]

## Security

⚠️ **Unaudited - Educational purposes only**

See [SECURITY.md](docs/SECURITY.md) for details.

## Development

```bash
# Install dependencies
forge install

# Run tests
forge test

# Coverage
forge coverage

# Deploy (testnet)
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
```

## Testing

- Unit tests: 95%+ coverage target
- Fuzz tests: Invariant testing
- Integration tests: Full user flows
- Static analysis: Slither + Aderyn

## License

MIT
