//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library Structs {
    struct Organization {
        uint256 organizationId;
        string name;
        string description;
        string website;
        address owner;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Recipient {
        uint256 recipientId;
        uint256 organizationId;
        string name;
        string email;
        string phone;
        string addressLine1;
        string addressLine2;
        string city;
        string state;
        string country;
        address walletAddress;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Payment {
        address recipient;
        address tokenAddress;
        uint256 amount;
        uint256 timestamp;
        string description;
    }

    struct AdvanceRequest {
        address recipient;
        uint256 amount;
        uint256 requestDate;
        uint256 approvalDate;
        uint256 repaymentDate;
        bool approved;
        bool repaid;
        address tokenAddress;
    }
}
