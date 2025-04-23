// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/OrganizationFactory.sol";
import "../src/contracts/OrganizationContract.sol" as OrgContract;
import "../src/libraries/structs.sol";

contract OrganizationFactoryTest is Test {
    OrganizationFactory public factory;
    address public owner;
    address public user;
    address public token;
    address public feeCollector;

    function setUp() public {
        owner = address(this);
        user = address(1);
        token = address(2);
        feeCollector = address(3);
        
        factory = new OrganizationFactory(feeCollector);
    }

    function testCreateOrganization() public {
        string memory name = "Test Org";
        string memory description = "Test Description";
        
        address orgAddress = factory.createOrganization(name, description);
        assertTrue(orgAddress != address(0), "Organization address should not be zero");
        
        // Verify organization contract details
        OrgContract.OrganizationContract org = OrgContract.OrganizationContract(orgAddress);
        assertEq(org.owner(), owner, "Owner should be set correctly");

        // Verify stored organization details
        Structs.Organization memory orgDetails = factory.getOrganizationDetails(owner);
        assertEq(orgDetails.name, name, "Organization name should be stored correctly");
        assertEq(orgDetails.description, description, "Organization description should be stored correctly");
        assertEq(orgDetails.owner, owner, "Owner should be stored correctly");
        assertTrue(orgDetails.organizationId != bytes32(0), "Organization ID should not be zero");
        assertEq(orgDetails.createdAt, block.timestamp, "Creation timestamp should be set correctly");
        assertEq(orgDetails.updatedAt, block.timestamp, "Update timestamp should be set correctly");
    }

    function testAddToken() public {
        string memory tokenName = "Test Token";
        
        factory.addToken(tokenName, token);
        assertTrue(factory.isTokenSupported(token), "Token should be supported");
        assertEq(factory.getTokenName(token), tokenName, "Token name should be set correctly");
    }

    function testRemoveToken() public {
        string memory tokenName = "Test Token";
        
        factory.addToken(tokenName, token);
        factory.removeToken(token);
        
        assertFalse(factory.isTokenSupported(token), "Token should not be supported");
        assertEq(bytes(factory.getTokenName(token)).length, 0, "Token name should be removed");
    }

    function testGetSupportedTokensCount() public {
        assertEq(factory.getSupportedTokensCount(), 0, "Initial count should be 0");
        
        factory.addToken("Token 1", address(1));
        assertEq(factory.getSupportedTokensCount(), 1, "Count should increase after adding token");
        
        factory.addToken("Token 2", address(2));
        assertEq(factory.getSupportedTokensCount(), 2, "Count should increase after adding another token");
        
        factory.removeToken(address(1));
        assertEq(factory.getSupportedTokensCount(), 1, "Count should decrease after removing token");
    }

    function test_RevertWhen_CreateOrganizationWithEmptyName() public {
        vm.expectRevert();
        factory.createOrganization("", "Test Description");
    }

    function test_RevertWhen_CreateOrganizationWithEmptyDescription() public {
        vm.expectRevert();
        factory.createOrganization("Test Org", "");
    }

    function test_RevertWhen_AddTokenWithEmptyName() public {
        vm.expectRevert();
        factory.addToken("", token);
    }

    function test_RevertWhen_AddTokenWithZeroAddress() public {
        vm.expectRevert();
        factory.addToken("Test Token", address(0));
    }

    function test_RevertWhen_AddExistingToken() public {
        factory.addToken("Test Token", token);
        vm.expectRevert();
        factory.addToken("Test Token", token);
    }

    function test_RevertWhen_RemoveNonExistentToken() public {
        vm.expectRevert();
        factory.removeToken(token);
    }

    function test_RevertWhen_RemoveTokenWithZeroAddress() public {
        vm.expectRevert();
        factory.removeToken(address(0));
    }

    function test_RevertWhen_GetTokenNameWithZeroAddress() public {
        vm.expectRevert();
        factory.getTokenName(address(0));
    }

    function test_RevertWhen_IsTokenSupportedWithZeroAddress() public {
        vm.expectRevert();
        factory.isTokenSupported(address(0));
    }

     function testUpdateOrganizationTransactionFee() public {
        // Create an organization first
        address orgOwner = address(1);
        vm.prank(orgOwner);
        address orgAddress = factory.createOrganization("Test Org", "Test Description");
        
        // Update transaction fee
        uint256 newFee = 30;
        factory.updateOrganizationTransactionFee(orgOwner, newFee);
        
        // Verify the fee was updated
        OrgContract.OrganizationContract org = OrgContract.OrganizationContract(orgAddress);
        assertEq(org.transactionFee(), newFee, "Transaction fee should be updated");
    }

    function testUpdateOrganizationFeeCollector() public {
        // Create an organization first
        address orgOwner = address(1);
        vm.prank(orgOwner);
        address orgAddress = factory.createOrganization("Test Org", "Test Description");
        
        // Update fee collector
        address newCollector = address(2);
        factory.updateOrganizationFeeCollector(orgOwner, newCollector);
        
        // Verify the fee collector was updated
        OrgContract.OrganizationContract org = OrgContract.OrganizationContract(orgAddress);
        assertEq(org.feeCollector(), newCollector, "Fee collector should be updated");
    }

    function test_RevertWhen_NonOwnerUpdatesTransactionFee() public {
        // Create an organization first
        address orgOwner = address(1);
        vm.prank(orgOwner);
        factory.createOrganization("Test Org", "Test Description");
        
        // Try to update fee as non-owner
        vm.prank(address(2));
        vm.expectRevert("Not authorized");
        factory.updateOrganizationTransactionFee(orgOwner, 30);
    }

    function test_RevertWhen_NonOwnerUpdatesFeeCollector() public {
        // Create an organization first
        address orgOwner = address(1);
        vm.prank(orgOwner);
        factory.createOrganization("Test Org", "Test Description");
        
        // Try to update fee collector as non-owner
        vm.prank(address(2));
        vm.expectRevert("Not authorized");
        factory.updateOrganizationFeeCollector(orgOwner, address(3));
    }

    function test_RevertWhen_UpdateTransactionFeeForNonExistentOrg() public {
        vm.expectRevert(CustomErrors.OrganizationNotFound.selector);
        factory.updateOrganizationTransactionFee(address(1), 30);
    }

    function test_RevertWhen_UpdateFeeCollectorForNonExistentOrg() public {
        vm.expectRevert(CustomErrors.OrganizationNotFound.selector);
        factory.updateOrganizationFeeCollector(address(1), address(2));
    }

    function test_RevertWhen_GetDetailsOfNonExistentOrg() public {
        vm.expectRevert(CustomErrors.OrganizationNotFound.selector);
        factory.getOrganizationDetails(address(1));
    }
} 