# EES (Ethereum Execution Service)

EES is public infrastructure for on-chain automation that enables developers to create applications requiring timely, reliable execution. The system is designed to provide excellent UX by allowing users to pay fees in any token and does not require token lockups. Automation is achieved by opening execution up to the public through financial incentivization.

## Key Features

- **Multi-token fee payments**: Users can pay execution fees in any ERC20 token
- **No token lockups**: Users don't need to lock tokens to create jobs
- **Public execution**: Anyone can become an executor and earn rewards
- **Designated executor system**: Uses commit-reveal scheme for fair executor selection
- **Modular architecture**: Extensible execution and fee modules
- **Staking and slashing**: Economic security through staking with slashing for misbehavior

## Architecture

EES consists of two main contracts:

### JobRegistry
The `JobRegistry` contract is responsible for storing and managing jobs. Users interact with `JobRegistry` to create and manage jobs, specifying the application they wish to call upon execution. Every job has an associated:
- **ExecutionModule**: Defines when a job can be executed (e.g., time intervals)
- **FeeModule**: Defines how execution fees are calculated (e.g., linear auctions)

### Coordinator
The `Coordinator` contract manages the executor ecosystem:
- **Executor coordination**: Handles staking, registration, and activation of executors
- **Job execution**: Coordinates execution during designated rounds and open competition periods
- **Reward distribution**: Distributes execution taxes to designated executors via epoch-based rewards
- **Slashing mechanism**: Penalizes inactive executors or those who commit but don't reveal

### Execution Flow

1. **Epoch Structure**: Time is divided into epochs, each containing multiple rounds
2. **Commit-Reveal Phase**: Executors commit and reveal signatures to generate randomness
3. **Designated Rounds**: Selected executors can execute jobs without paying execution tax
4. **Open Competition**: Outside rounds, anyone can execute jobs by paying execution tax
5. **Reward Distribution**: At epoch end, execution taxes are distributed to active executors

## Security Disclaimer

⚠️ **WARNING: This code has not been audited. Use at your own risk.**

The EES contracts are experimental software and may contain bugs or vulnerabilities. While the code is being built in public and follows best practices, it has not undergone formal security audits. Users should:
- Conduct their own security review before using in production
- Start with small amounts when testing
- Be aware that funds may be at risk
- Monitor the contracts for any issues

The developers make no warranties or representations regarding the security, functionality, or fitness for any particular purpose of this software.

## Base Mainnet Deployment

The following contracts are deployed on Base mainnet:

| Contract | Address |
|----------|---------|
| **Coordinator** | [`0x5bfA0174f777dEbe077DF263CBf678410417664A`](https://basescan.org/address/0x5bfA0174f777dEbe077DF263CBf678410417664A) |
| **JobRegistry** | [`0xC0960a9374EBbF02185D4951200ffe64809dA41C`](https://basescan.org/address/0xC0960a9374EBbF02185D4951200ffe64809dA41C) |
| **RegularTimeInterval** (Execution Module) | [`0xC21b88a1d1652A6d1Ff8cfb3D9afd6CcDbd04B02`](https://basescan.org/address/0xC21b88a1d1652A6d1Ff8cfb3D9afd6CcDbd04B02) |
| **LinearAuction** (Fee Module) | [`0xE1BFEc98aFF4A5D612e4f669B5D7390a67a1A356`](https://basescan.org/address/0xE1BFEc98aFF4A5D612e4f669B5D7390a67a1A356) |

## Documentation

For more detailed documentation, visit [docs.ees.xyz](https://docs.ees.xyz).

## License

MIT

