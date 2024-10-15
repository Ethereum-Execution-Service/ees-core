# EES

EES (Ethereum Execution Service) is public infrastructure for on-chain automation. Developers can create applications on top of EES which benefit from timely execution. EES is designed to provide good UX enabling users to pay fees in any token and does not require token lockups. Automation is achieved by opening execution up to the public through financial incentivization. The code is being built in public and has not yet been audited, so use at your own risk. More info will come soon. For now, you can read more [here](https://docs.ees.xyz).

## Architecture
EES consists mainly of two contracts: JobRegistry and Coordinator. The JobRegistry contract is responsible for storing and managing jobs. Users interact with JobRegistry to create and manage jobs, specifying the application they wish to call upon execution. Every job has an associated ExecutionModule and FeeModule containing execution logic and fee logic respectively. The Coordinator contract is responsible for coordination of executors including job execution, staking and slashing.

