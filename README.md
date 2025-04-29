# PayTroix Smart Contracts

This repository contains the smart contracts for the PayTroix project, a blockchain-based solution for managing organizations and their operations. The project is built using [Foundry](https://book.getfoundry.sh/), a modern development framework for Ethereum smart contracts.

## Deployed Contracts

### Lisk Sepolia Network
- **OrganizationFactory**: [0xe1db6db5f799feeb969088ac1ec7072b295a55a0](https://sepolia-blockscout.lisk.com/address/0xe1db6db5f799feeb969088ac1ec7072b295a55a0)
- **OrganizationContract**: [0xe90d6a043c34ab9c03f541e99c21dbe48d14e92b](https://sepolia-blockscout.lisk.com/address/0xe90d6a043c34ab9c03f541e99c21dbe48d14e92b)

### Base Sepolia Network
- **OrganizationFactory**: [0x3677f7827760016702d034837bd2fb8e6ba618dd](https://sepolia.basescan.org/address/0x3677f7827760016702d034837bd2fb8e6ba618dd)
- **OrganizationContract**: [0xab9929600ad5026431ca61e742d5a224f205fe23](https://sepolia.basescan.org/address/0xab9929600ad5026431ca61e742d5a224f205fe23)

## Table of Contents
- [Overview](#overview)
- [Smart Contract Architecture](#smart-contract-architecture)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## Overview

PayTroix is a decentralized blockchain-based payroll platform designed for forward-thinking organizations seeking to leverage Web3 technology for employee compensation. The platform enables instant salary payments, enhanced privacy, decentralized record-keeping, and access to financial wellness tools through smart contract technology.

### Key Features
- Organization creation and management
- Role-based access control
- Token management system
- Secure contract interactions
- Comprehensive test coverage
- Gas-efficient operations

## Smart Contract Architecture

### OrganizationFactory
The factory contract is responsible for creating and managing organization instances. Key functionalities include:
- Organization deployment
- Organization registry management
- Organization address resolution
- Factory-level access control

### OrganizationContract
The main organization contract that implements core business logic:
- Member management
- Role-based permissions
- Organization settings
- Token operations
- Contract interactions

### Tokens
A utility contract for managing token-related operations:
- Token transfers
- Balance management
- Token approvals
- Token metadata

## Project Structure

```
Contracts/
├── src/
│   ├── contracts/           # Main contract implementations
│   │   ├── OrganizationContract.sol
│   │   ├── OrganizationFactory.sol
│   │   └── Tokens.sol
│   ├── interfaces/          # Contract interfaces
│   └── libraries/           # Shared libraries and utilities
├── script/                  # Deployment scripts
├── test/                   # Contract test files
├── lib/                    # Dependencies and libraries
└── out/                    # Compiled contracts
```

## Installation

1. **Prerequisites**
   - [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
   - Git
   - Node.js (for additional tooling)

2. **Clone and Setup**
   ```bash
   git clone https://github.com/Web3-gen/Contracts
   cd Contracts
   forge install
   ```

## Development

### Compiling Contracts
```bash
forge build
```

### Running Tests
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract OrganizationFactoryTest

# Run with gas reporting
forge test --gas-report
```

### Code Quality
```bash
# Format code
forge fmt

# Check for vulnerabilities
forge inspect OrganizationContract.sol
```

## Testing

The project includes comprehensive tests for all smart contracts. Test files are located in the `test/` directory:

- OrganizationContract.t.sol
- OrganizationFactory.t.sol
- Token.t.sol

To run specific tests with detailed output:
```bash
forge test -vv
```

## Deployment

### Local Development
```bash
forge script script/deploy.s.sol --fork-url http://localhost:8545 --broadcast
```

### Testnet Deployment
```bash
forge script script/deploy.s.sol --rpc-url <testnet-rpc> --private-key <pk> --broadcast --verify
```

### Mainnet Deployment
```bash
forge script script/deploy.s.sol --rpc-url <mainnet-rpc> --private-key <pk> --broadcast --verify
```

## Security

The contracts have been designed with security in mind:
- Comprehensive test coverage
- Access control mechanisms
- Reentrancy protection
- Gas optimization
- Input validation

For security audits and reports, please refer to the `audits/` directory.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

Please ensure all tests pass and follow the project's coding standards.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
