//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Structs {
    struct Organization {
        bytes32 organizationId;
        string name;
        string description;
        address owner;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Recipient {
        bytes32 recipientId;
        bytes32 organizationId;
        string name;
        uint256 salaryAmount;
        uint256 advanceCollected;
        address walletAddress;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Payment {
        address recipient;
        address tokenAddress;
        uint256 amount;
        uint256 timestamp;
    }

    struct AdvanceRequest {
        address recipient;
        uint256 amount;
        uint256 requestDate;
        uint256 approvalDate;
        bool approved;
        bool repaid;
        address tokenAddress;
    }
}
