// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/OrganizationFactory.sol";
import "../src/contracts/OrganizationContract.sol" as OrgContract;
import "../src/libraries/structs.sol";
import "../src/libraries/errors.sol";

contract OrganizationFactoryTest is Test {
    // Events from OrganizationFactory contract
    event OrganizationCreated(
        address indexed organizationAddress, address indexed owner, string name, string description, uint256 createdAt
    );

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
        vm.expectRevert(CustomErrors.NameRequired.selector);
        factory.createOrganization("", "Test Description");
    }

    function test_RevertWhen_CreateOrganizationWithEmptyDescription() public {
        vm.expectRevert(CustomErrors.DescriptionRequired.selector);
        factory.createOrganization("Test Org", "");
    }

    function test_RevertWhen_AddTokenWithEmptyName() public {
        vm.expectRevert(CustomErrors.InvalidTokenName.selector);
        factory.addToken("", token);
    }

    function test_RevertWhen_AddTokenWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        factory.addToken("Test Token", address(0));
    }

    function test_RevertWhen_AddExistingToken() public {
        factory.addToken("Test Token", token);
        vm.expectRevert(CustomErrors.TokenAlreadySupported.selector);
        factory.addToken("Test Token", token);
    }

    function test_RevertWhen_RemoveNonExistentToken() public {
        vm.expectRevert(CustomErrors.InvalidToken.selector);
        factory.removeToken(token);
    }

    function test_RevertWhen_RemoveTokenWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidToken.selector);
        factory.removeToken(address(0));
    }

    function test_RevertWhen_GetTokenNameWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        factory.getTokenName(address(0));
    }

    function test_RevertWhen_IsTokenSupportedWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
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
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        factory.updateOrganizationTransactionFee(orgOwner, 30);
    }

    function test_RevertWhen_NonOwnerUpdatesFeeCollector() public {
        // Create an organization first
        address orgOwner = address(1);
        vm.prank(orgOwner);
        factory.createOrganization("Test Org", "Test Description");

        // Try to update fee collector as non-owner
        vm.prank(address(2));
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
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

    function testGetOrganizationContract() public {
        // Initially should return zero address
        assertEq(factory.getOrganizationContract(user), address(0), "Should return zero address for non-existent org");

        // Create organization
        vm.prank(user);
        address orgAddress = factory.createOrganization("Test Org", "Test Description");

        // Should return correct address after creation
        assertEq(factory.getOrganizationContract(user), orgAddress, "Should return correct organization address");
    }

    function test_RevertWhen_CreateDuplicateOrganization() public {
        // Create first organization
        vm.startPrank(user);
        factory.createOrganization("First Org", "First Description");

        // Try to create second organization with same owner
        vm.expectRevert(CustomErrors.OrganizationAlreadyExists.selector);
        factory.createOrganization("Second Org", "Second Description");
        vm.stopPrank();
    }

    function testOrganizationCreatedEvent() public {
        string memory name = "Test Org";
        string memory description = "Test Description";

        // Test event emission
        vm.recordLogs();
        address orgAddress = factory.createOrganization(name, description);

        // Get the emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length > 0, true, "Should emit at least one event");

        // The event we're interested in should be the last one
        Vm.Log memory lastEntry = entries[entries.length - 1];

        // Verify event signature
        bytes32 expectedEventSig = keccak256("OrganizationCreated(address,address,string,string,uint256)");
        assertEq(lastEntry.topics[0], expectedEventSig, "Event signature should match");

        // Verify indexed parameters
        assertEq(address(uint160(uint256(lastEntry.topics[1]))), orgAddress, "Organization address should match");
        assertEq(address(uint160(uint256(lastEntry.topics[2]))), address(this), "Owner address should match");

        // Decode non-indexed parameters
        (string memory emittedName, string memory emittedDesc, uint256 emittedTime) =
            abi.decode(lastEntry.data, (string, string, uint256));

        // Verify non-indexed parameters
        assertEq(emittedName, name, "Organization name should match");
        assertEq(emittedDesc, description, "Organization description should match");
        assertEq(emittedTime, block.timestamp, "Creation timestamp should match");
    }

    function testConstructorAndInitialState() public {
        // Test constructor parameters
        assertEq(factory.owner(), address(this), "Owner should be set correctly");
        assertEq(factory.feeCollector(), feeCollector, "Fee collector should be set correctly");

        // Test initial state
        assertEq(factory.getSupportedTokensCount(), 0, "Initial token count should be zero");
        assertEq(factory.getOrganizationContract(address(this)), address(0), "Initial org contract should be zero");
    }

    function testCompleteOrganizationLifecycle() public {
        // Create organization
        string memory name = "Test Org";
        string memory description = "Test Description";
        address orgAddress = factory.createOrganization(name, description);

        // Add supported token
        factory.addToken("Test Token", token);

        // Update organization settings
        factory.updateOrganizationTransactionFee(address(this), 30);
        factory.updateOrganizationFeeCollector(address(this), address(4));

        // Verify final state
        OrgContract.OrganizationContract org = OrgContract.OrganizationContract(orgAddress);
        assertEq(org.transactionFee(), 30, "Transaction fee should be updated");
        assertEq(org.feeCollector(), address(4), "Fee collector should be updated");
        assertTrue(factory.isTokenSupported(token), "Token should be supported");

        // Get and verify organization details
        Structs.Organization memory orgDetails = factory.getOrganizationDetails(address(this));
        assertEq(orgDetails.name, name, "Name should match");
        assertEq(orgDetails.description, description, "Description should match");
        assertEq(orgDetails.owner, address(this), "Owner should match");
    }
}
