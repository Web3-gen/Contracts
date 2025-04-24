//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import {OrganizationFactory} from "../src/contracts/OrganizationFactory.sol";
import {OrganizationContract} from "../src/contracts/OrganizationContract.sol";


contract OrganizationScript is Script {
    address public organizationAddress;
    address public recipientAddress;
    address public tokenAddress;

    function setUp() public {
        // organizationAddress = vm.envAddress("ORGANIZATION_ADDRESS");
        recipientAddress = vm.envAddress("RECIPIENT_ADDRESS");
        tokenAddress = vm.envAddress("TOKEN_ADDRESS");
    }

    function run() public {
        vm.startBroadcast();
        // Deploy the OrganizationFactory contract
        OrganizationFactory organizationFactory = new OrganizationFactory(
            vm.envAddress("FEE_COLLECTOR_ADDRESS")
        );
        console.log("OrganizationFactory deployed at:", address(organizationFactory));
    
        // Create a new organization
        organizationAddress = organizationFactory.createOrganization(
            "My Organization",
            "This is a description of my organization."
        );
        console.log("Organization created at:", organizationAddress);

        // Add a token to the organization
        organizationFactory.addToken("MyToken", tokenAddress);
        console.log("Token added:", tokenAddress);

        // Create a new recipient
        OrganizationContract(organizationAddress).createRecipient(
            recipientAddress,
            "John Doe",
            1000
        );
        console.log("Recipient created at:", recipientAddress);
        

        
        vm.stopBroadcast();
    }
}