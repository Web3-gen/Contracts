# PayTroix_Project_Web3Bridge

This repository contains the smart contracts and related scripts for the HR_Project_Web3Bridge, a blockchain-based solution for managing organizations and contracts. The project leverages [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment of Solidity smart contracts.

## Deployed Contracts (Lisk Sepolia Network)

- **OrganizationFactory**: [0xe1db6db5f799feeb969088ac1ec7072b295a55a0](https://sepolia-blockscout.lisk.com/address/0xe1db6db5f799feeb969088ac1ec7072b295a55a0)
- **OrganizationContract**: [0xe90d6a043c34ab9c03f541e99c21dbe48d14e92b](https://sepolia-blockscout.lisk.com/address/0xe90d6a043c34ab9c03f541e99c21dbe48d14e92b)

## Deployed Contracts (Base Sepolia Network)

- **OrganizationFactory**: [0x3677f7827760016702d034837bd2fb8e6ba618dd](https://sepolia.basescan.org/address/0x3677f7827760016702d034837bd2fb8e6ba618dd)
- **OrganizationContract**: [0xab9929600ad5026431ca61e742d5a224f205fe23](https://sepolia.basescan.org/address/0xab9929600ad5026431ca61e742d5a224f205fe23)

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Usage](#usage)
- [Smart Contracts](#smart-contracts)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [License](#license)

## Overview

HR_Project_Web3Bridge is a decentralized solution that enables organizations to manage their operations on the blockchain. The project consists of multiple smart contracts that handle organization creation, management, and token operations.

### Key Features

- Organization creation and management
- Token management system
- Secure contract interactions
- Full test coverage
- Foundry-based development environment

## Project Structure

```
contracts/
├── src/
│   ├── contracts/           # Main contract implementations
│   ├── interfaces/          # Contract interfaces
│   └── libraries/           # Shared libraries and utilities
├── script/                  # Deployment scripts
├── test/                   # Contract test files
└── lib/                    # Dependencies and libraries
```

## Installation

1. **Prerequisites**
   - [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
   - Git

2. **Clone the Repository**
   ```bash
   git clone <repository-url>
   cd HR_Project_Web3Bridge/contracts
   ```

3. **Install Dependencies**
   ```bash
   forge install
   ```

## Usage

### Compiling Contracts
```bash
forge build
```

### Running Tests
```bash
forge test
```

### Deploying Contracts
```bash
forge script script/deploy.s.sol --rpc-url <your-rpc-url> --private-key <your-private-key> --broadcast
```

## Smart Contracts

### OrganizationFactory
- Main contract for creating and managing organizations
- Handles organization deployment and registration
- Maintains organization registry

### OrganizationContract
- Implements organization-specific logic
- Manages organization members and roles
- Handles organization-specific operations

### Additional Components
- **IERC20.sol**: Standard ERC20 interface implementation
- **Tokens.sol**: Token management functionality
- **errors.sol**: Custom error definitions
- **structs.sol**: Shared data structures

## Testing

The project includes comprehensive tests for all smart contracts. Test files are located in the `test/` directory:

- OrganizationContract.t.sol
- OrganizationFactory.t.sol
- Token.t.sol

To run specific tests:
```bash
forge test --match-contract OrganizationFactoryTest
```

## Deployment

The project uses Foundry's deployment system through scripts in the `script/` directory. The main deployment script is `deploy.s.sol`.

### Deployment Commands
```bash
# Deploy to local network
forge script script/deploy.s.sol --fork-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/deploy.s.sol --rpc-url <testnet-rpc> --private-key <pk> --broadcast --verify
```

### Verification Commands
Verification commands can be found in `verify_command.txt`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request
