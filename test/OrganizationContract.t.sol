// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/OrganizationContract.sol" as OrgContract;
import "../src/contracts/OrganizationFactory.sol";
import "../src/interfaces/IERC20.sol";
import "../src/libraries/structs.sol" as StructLib;
import "../src/libraries/errors.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    uint256 internal _totalSupply;

    function totalSupply() external view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Transfer to zero address");

        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(to != address(0), "Transfer to zero address");

        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        require(spender != address(0), "Approve to zero address");

        _allowances[msg.sender][spender] = amount;
        return true;
    }

    // Helper function for testing
    function mint(address account, uint256 amount) external virtual {
        require(account != address(0), "Mint to zero address");

        _balances[account] += amount;
        _totalSupply += amount;
    }
}

contract OrganizationContractTest is Test {
    // Events from OrganizationContract for testing
    event RecipientCreated(bytes32 indexed recipientId, address indexed walletAddress, string name);
    event TokenDisbursed(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event BatchDisbursement(address indexed tokenAddress, uint256 recipientCount, uint256 totalAmount);

    OrganizationFactory public factory;
    OrgContract.OrganizationContract public org;
    MockERC20 public token;
    address public owner;
    address public user;
    address public recipient;
    address public feeCollector;

    function setUp() public {
        owner = address(this);
        user = address(1);
        recipient = address(2);
        feeCollector = address(3);

        factory = new OrganizationFactory(feeCollector);
        address orgAddress = factory.createOrganization("Test Org", "Test Description");
        org = OrgContract.OrganizationContract(orgAddress);

        token = new MockERC20();

        // Set up initial token balances
        token.mint(owner, 1000 ether);
        token.mint(user, 1000 ether);

        // Approve organization to spend tokens
        token.approve(address(org), type(uint256).max);

        // Add token to supported tokens
        factory.addToken("Test Token", address(token));
    }

    function testCreateRecipient() public {
        string memory name = "Test Recipient";
        uint256 salary = 1000;

        bytes32 recipientId = org.createRecipient(recipient, name, salary);
        assertTrue(recipientId != bytes32(0), "Recipient ID should not be zero");

        StructLib.Structs.Recipient memory recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.salaryAmount, salary, "Salary should be set correctly");
    }

    function testDisburseToken() public {
        // Create recipient first
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Disburse tokens
        uint256 amount = 100;
        bool success = org.disburseToken(address(token), recipient, amount);
        assertTrue(success, "Token disbursement should succeed");

        // Check balances
        uint256 fee = (amount * org.transactionFee()) / 10000;
        assertEq(token.balanceOf(recipient), amount - fee, "Recipient should receive correct amount");
        assertEq(token.balanceOf(feeCollector), fee, "Fee collector should receive correct fee");

        StructLib.Structs.Payment[] memory payments = org.getRecipientPayments(recipient);
        assertEq(payments[0].amount, amount - fee, "Payment history should record amount minus fee");
    }

    function testRequestAdvance() public {
        // Create recipient first
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Set advance limit
        org.setRecipientAdvanceLimit(recipient, 500);

        // Request advance
        uint256 amount = 300;

        vm.prank(recipient);
        org.requestAdvance(amount, address(token));

        // Advance time by 1 second to ensure approval date is after request date
        vm.warp(block.timestamp + 1);

        // Approve the advance request
        org.approveAdvance(recipient);

        // Get advance request
        (
            address requestRecipient,
            uint256 requestAmount,
            uint256 requestDate,
            uint256 approvalDate,
            bool approved,
            bool repaid,
            address requestToken
        ) = org.advanceRequests(recipient);

        // Verify advance request details
        assertEq(requestRecipient, recipient, "Recipient address mismatch");
        assertEq(requestAmount, amount, "Request amount mismatch");
        assertEq(requestToken, address(token), "Token address mismatch");
        assertTrue(approved, "Request should be approved");
        assertFalse(repaid, "Request should not be repaid yet");
        assertGt(approvalDate, requestDate, "Approval date should be after request date");
    }

    function testRequestAdvanceWithMaxLimit() public {
        // Create recipient with salary
        uint256 salary = 1000;
        org.createRecipient(recipient, "Test Recipient", salary);

        // Set advance limit to 50% of salary
        uint256 advanceLimit = salary / 2;
        org.setRecipientAdvanceLimit(recipient, advanceLimit);

        // Request maximum allowed advance
        vm.prank(recipient);
        org.requestAdvance(advanceLimit, address(token));

        // Verify request details
        (address requestRecipient, uint256 requestAmount,,,,, address requestToken) = org.advanceRequests(recipient);
        assertEq(requestRecipient, recipient, "Recipient should be set correctly");
        assertEq(requestAmount, advanceLimit, "Amount should be set to maximum limit");
        assertEq(requestToken, address(token), "Token should be set correctly");
    }

    function test_RevertWhen_RequestZeroAdvance() public {
        // Create recipient
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        // Try to request zero advance
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.requestAdvance(0, address(token));
    }

    function test_RevertWhen_NonRecipientRequestsAdvance() public {
        // Try to request advance without being a recipient
        vm.prank(address(999));
        vm.expectRevert(CustomErrors.RecipientNotFound.selector);
        org.requestAdvance(100, address(token));
    }

    function test_RevertWhen_RequestAdvanceAboveDefaultLimit() public {
        // Create recipient with default advance limit (0.1 ether)
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Try to request advance above the default limit
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.requestAdvance(0.2 ether, address(token));  // Request more than default 0.1 ether limit
    }

    function testRequestAdvanceEventEmission() public {
        // Create recipient and set limit
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        // Record events
        vm.recordLogs();

        // Request advance
        vm.prank(recipient);
        org.requestAdvance(300, address(token));

        // Get emitted events
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Verify AdvanceRequested event
        bytes32 expectedEventSig = keccak256("AdvanceRequested(address,uint256)");
        bool foundEvent = false;
        
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedEventSig) {
                foundEvent = true;
                assertEq(address(uint160(uint256(entries[i].topics[1]))), recipient, "Recipient address should match");
                assertEq(abi.decode(entries[i].data, (uint256)), 300, "Amount should match");
                break;
            }
        }
        
        assertTrue(foundEvent, "Should emit AdvanceRequested event");
    }

    function test_RevertWhen_RequestAdvanceWithUnsupportedToken() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidToken.selector);
        org.requestAdvance(100, address(999));
    }

    function testApproveAdvance() public {
        // Create recipient first
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Set advance limit
        org.setRecipientAdvanceLimit(recipient, 500);

        // Request advance
        uint256 amount = 300;

        vm.prank(recipient);
        org.requestAdvance(amount, address(token));

        // Approve advance
        bool success = org.approveAdvance(recipient);
        assertTrue(success, "Advance approval should succeed");

        // Verify balances
        assertEq(token.balanceOf(recipient), amount, "Recipient should receive advance amount");
    }

    function test_RevertWhen_DisburseTokenToInvalidRecipient() public {
        vm.expectRevert();
        org.disburseToken(address(token), address(0), 100);
    }

    function test_RevertWhen_DisburseTokenWithInsufficientBalance() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        // Remove the token approval to ensure insufficient allowance
        token.approve(address(org), 0);
        vm.expectRevert();
        org.disburseToken(address(token), recipient, 100);
    }

    function testBatchCreateRecipients() public {
        address[] memory addresses = new address[](2);
        string[] memory names = new string[](2);
        uint256[] memory salaries = new uint256[](2);

        addresses[0] = address(1);
        addresses[1] = address(2);
        names[0] = "Recipient 1";
        names[1] = "Recipient 2";
        salaries[0] = 1000;
        salaries[1] = 2000;

        org.batchCreateRecipients(addresses, names, salaries);

        StructLib.Structs.Recipient memory recipient1 = org.getRecipient(addresses[0]);
        StructLib.Structs.Recipient memory recipient2 = org.getRecipient(addresses[1]);

        assertEq(recipient1.salaryAmount, 1000, "Salary should be set correctly for recipient 1");
        assertEq(recipient2.salaryAmount, 2000, "Salary should be set correctly for recipient 2");
    }

    function testBatchDisburseToken() public {
        // Create recipients
        address[] memory recipients = new address[](2);
        string[] memory names = new string[](2);
        uint256[] memory amounts = new uint256[](2);

        recipients[0] = address(1);
        recipients[1] = address(2);
        names[0] = "Recipient 1";
        names[1] = "Recipient 2";
        amounts[0] = 100 * 10 ** 18; // 100 tokens with 18 decimals
        amounts[1] = 200 * 10 ** 18; // 200 tokens with 18 decimals

        org.batchCreateRecipients(recipients, names, amounts);

        // Calculate total amount including fees
        uint256 totalNetAmount = amounts[0] + amounts[1];
        uint256 totalGrossAmount = (totalNetAmount * 10000) / (10000 - org.transactionFee());
        uint256 totalFees = totalGrossAmount - totalNetAmount;

        // Store initial balances
        uint256 initialBalance1 = token.balanceOf(recipients[0]);
        uint256 initialBalance2 = token.balanceOf(recipients[1]);
        uint256 initialFeeCollectorBalance = token.balanceOf(feeCollector);

        // Mint and approve tokens for gross amount
        token.mint(owner, totalGrossAmount);
        token.approve(address(org), totalGrossAmount);

        // Disburse tokens
        bool success = org.batchDisburseToken(address(token), recipients, amounts);
        assertTrue(success, "Batch disbursement should succeed");

        // Check balance differences
        assertEq(
            token.balanceOf(recipients[0]) - initialBalance1, amounts[0], "Recipient 1 should receive correct amount"
        );
        assertEq(
            token.balanceOf(recipients[1]) - initialBalance2, amounts[1], "Recipient 2 should receive correct amount"
        );
        assertEq(
            token.balanceOf(feeCollector) - initialFeeCollectorBalance,
            totalFees - 1,
            "Fee collector should receive correct fee"
        );
    }

    function testSetRecipientAdvanceLimit() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        uint256 newLimit = 200;
        org.setRecipientAdvanceLimit(recipient, newLimit);
        assertEq(org.recipientAdvanceLimit(recipient), newLimit, "Advance limit should be updated");
    }

    function test_RevertWhen_DisburseTokenWithUnpaidAdvance() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        uint256 amount = 300;

        vm.prank(recipient);
        org.requestAdvance(amount, address(token));

        // Approve advance
        org.approveAdvance(recipient);

        // Ensure we have enough tokens for the disbursement but not enough to cover the advance
        token.mint(owner, amount - 1);
        token.approve(address(org), amount - 1);

        // Try to disburse less than the advance amount
        vm.expectRevert();
        org.disburseToken(address(token), recipient, amount - 1);
    }

    function testSetTransactionFee() public {
        uint256 newFee = 30;
        factory.updateOrganizationTransactionFee(owner, newFee);
        assertEq(org.transactionFee(), newFee, "Transaction fee should be updated");
    }

    function test_RevertWhen_SetTransactionFeeTooHigh() public {
        uint256 newFee = 81;
        vm.expectRevert(CustomErrors.InvalidFee.selector);
        factory.updateOrganizationTransactionFee(owner, newFee);
    }

    function testSetFeeCollector() public {
        address newCollector = address(4);
        factory.updateOrganizationFeeCollector(owner, newCollector);
        assertEq(org.feeCollector(), newCollector, "Fee collector should be updated");
    }

    function test_RevertWhen_SetFeeCollectorToZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidAddress.selector);
        factory.updateOrganizationFeeCollector(owner, address(0));
    }

    function test_RevertWhen_BatchCreateRecipientsInvalidInput() public {
        address[] memory addresses = new address[](2);
        string[] memory names = new string[](1);
        uint256[] memory salaries = new uint256[](2);

        vm.expectRevert();
        org.batchCreateRecipients(addresses, names, salaries);
    }

    function test_RevertWhen_BatchDisburseTokenInvalidInput() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert();
        org.batchDisburseToken(address(token), recipients, amounts);
    }

    function test_RevertWhen_DisburseTokenWithZeroAmount() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        vm.expectRevert();
        org.disburseToken(address(token), recipient, 0);
    }

    function test_RevertWhen_DisburseTokenWithUnsupportedToken() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        vm.expectRevert();
        org.disburseToken(address(3), recipient, 100);
    }

    function test_RevertWhen_RequestAdvanceExceedsLimit() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        vm.prank(recipient);
        vm.expectRevert();
        org.requestAdvance(501, address(token));
    }

    function test_RevertWhen_ApproveAdvanceForNonExistentRecipient() public {
        vm.expectRevert();
        org.approveAdvance(recipient);
    }

    function testUpdateOrganizationInfo() public {
        string memory newName = "Updated Org Name";
        string memory newDescription = "Updated Description";
        
        org.updateOrganizationInfo(newName, newDescription);
        
        (bytes32 id, string memory name, string memory description, , , ) = org.organizationInfo();
        assertEq(name, newName, "Organization name should be updated");
        assertEq(description, newDescription, "Organization description should be updated");
    }

    function test_RevertWhen_UpdateOrgInfoEmptyName() public {
        vm.expectRevert(CustomErrors.NameRequired.selector);
        org.updateOrganizationInfo("", "Valid Description");
    }

    function test_RevertWhen_UpdateOrgInfoEmptyDescription() public {
        vm.expectRevert(CustomErrors.DescriptionRequired.selector);
        org.updateOrganizationInfo("Valid Name", "");
    }

    function test_RevertWhen_UnauthorizedUpdateOrgInfo() public {
        vm.prank(user);
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        org.updateOrganizationInfo("New Name", "New Description");
    }

    function testUpdateRecipient() public {
        org.createRecipient(recipient, "Original Name", 1000);

        // Store initial timestamp
        StructLib.Structs.Recipient memory initial = org.getRecipient(recipient);

        // Advance time by 1 second
        vm.warp(block.timestamp + 1);

        org.updateRecipient(recipient, "Updated Name");

        StructLib.Structs.Recipient memory updated = org.getRecipient(recipient);
        assertEq(updated.name, "Updated Name", "Recipient name should be updated");
        assertTrue(updated.updatedAt > initial.createdAt, "Updated timestamp should be greater than created timestamp");
    }

    function test_RevertWhen_UpdateNonExistentRecipient() public {
        vm.expectRevert(CustomErrors.RecipientNotFound.selector);
        org.updateRecipient(address(999), "New Name");
    }

    function test_RevertWhen_UpdateRecipientEmptyName() public {
        org.createRecipient(recipient, "Original Name", 1000);
        vm.expectRevert(CustomErrors.NameRequired.selector);
        org.updateRecipient(recipient, "");
    }

    function test_RevertWhen_CreateDuplicateRecipient() public {
        org.createRecipient(recipient, "Original Name", 1000);
        vm.expectRevert(CustomErrors.RecipientAlreadyExists.selector);
        org.createRecipient(recipient, "Another Name", 2000);
    }

    function testGetAllPayments() public {
        // Create two recipients
        address recipient1 = address(4);
        address recipient2 = address(5);
        org.createRecipient(recipient1, "Recipient 1", 1000);
        org.createRecipient(recipient2, "Recipient 2", 2000);

        // Make payments
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;

        token.mint(owner, 1000 ether);
        token.approve(address(org), type(uint256).max);

        org.disburseToken(address(token), recipient1, amount1);
        org.disburseToken(address(token), recipient2, amount2);

        StructLib.Structs.Payment[] memory payments = org.getAllPayments();
        assertEq(payments.length, 2, "Should have two payments");

        assertEq(payments[0].amount, amount1, "First payment amount should be correct");
        assertEq(payments[0].recipient, recipient1, "First payment recipient should be correct");

        assertEq(payments[1].amount, amount2, "Second payment amount should be correct");
        assertEq(payments[1].recipient, recipient2, "Second payment recipient should be correct");
    }

    function testGetRecipientPayments() public {
        // Create recipient and make multiple payments
        org.createRecipient(recipient, "Test Recipient", 1000);

        token.mint(owner, 1000 ether);
        token.approve(address(org), type(uint256).max);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        for (uint256 i = 0; i < amounts.length; i++) {
            org.disburseToken(address(token), recipient, amounts[i]);
        }

        StructLib.Structs.Payment[] memory payments = org.getRecipientPayments(recipient);
        assertEq(payments.length, 3, "Should have three payments");

        for (uint256 i = 0; i < payments.length; i++) {
            assertEq(payments[i].amount, amounts[i], "Payment amount should be correct");
            assertEq(payments[i].recipient, recipient, "Payment recipient should be correct");
        }
    }

    function testMultipleAdvanceRequests() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        // First advance request
        vm.startPrank(recipient);
        org.requestAdvance(200, address(token));
        
        // Approve first request
        vm.stopPrank();
        org.approveAdvance(recipient);

        // Try second advance request (should fail as first one is not repaid)
        vm.startPrank(recipient);
        vm.expectRevert(CustomErrors.InvalidRequest.selector);
        org.requestAdvance(300, address(token));
        vm.stopPrank();
    }

    function testSetDefaultAdvanceLimit() public {
        uint256 newLimit = 1000 ether;
        org.setDefaultAdvanceLimit(newLimit);

        // Create new recipient and verify they get new default limit
        address newRecipient = address(6);
        org.createRecipient(newRecipient, "New Recipient", 2000);
        assertEq(org.recipientAdvanceLimit(newRecipient), newLimit, "New recipient should get default advance limit");
    }

    function testRecipientCreatedEvent() public {
        vm.expectEmit(true, true, false, true);
        emit RecipientCreated(
            bytes32(keccak256(abi.encodePacked(recipient, block.timestamp))), recipient, "Test Recipient"
        );
        org.createRecipient(recipient, "Test Recipient", 1000);
    }

    function testTokenDisbursedEvent() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        uint256 amount = 100 ether;

        vm.expectEmit(true, true, false, true);
        emit TokenDisbursed(address(token), recipient, amount);
        org.disburseToken(address(token), recipient, amount);
    }

    function testBatchDisbursementEvent() public {
        address[] memory recipients = new address[](2);
        string[] memory names = new string[](2);
        uint256[] memory amounts = new uint256[](2);

        recipients[0] = address(1);
        recipients[1] = address(2);
        names[0] = "Recipient 1";
        names[1] = "Recipient 2";
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        org.batchCreateRecipients(recipients, names, amounts);

        uint256 totalNetAmount = amounts[0] + amounts[1];
        uint256 totalGrossAmount = (totalNetAmount * 10000) / (10000 - org.transactionFee());

        token.mint(owner, totalGrossAmount);
        token.approve(address(org), totalGrossAmount);

        vm.expectEmit(true, false, false, true);
        emit BatchDisbursement(address(token), 2, totalGrossAmount - 1); // Account for rounding down
        org.batchDisburseToken(address(token), recipients, amounts);
    }

    function testPaymentHistoryTracking() public {
        // Create recipient and disburse tokens
        org.createRecipient(recipient, "Test Recipient", 1000);
        uint256 amount = 100;
        org.disburseToken(address(token), recipient, amount);
        
        // Get payment history
        StructLib.Structs.Payment[] memory payments = org.getRecipientPayments(recipient);
        assertEq(payments.length, 1, "Should have one payment record");
        assertEq(payments[0].recipient, recipient, "Payment recipient should match");
        assertEq(payments[0].amount, amount - (amount * org.transactionFee()) / 10000, "Payment amount should match");
    }

    function testFeeCalculationEdgeCases() public {
        // Test with very small amounts
        uint256 smallAmount = 1;
        uint256 fee = org.calculateFee(smallAmount);
        assertEq(fee, 0, "Fee should be 0 for very small amounts");

        // Test with large amounts
        uint256 largeAmount = type(uint256).max / 10001; // Prevent overflow
        uint256 largeFee = org.calculateFee(largeAmount);
        assertTrue(largeFee > 0, "Fee should be calculated for large amounts");
        
        // Test gross amount calculation
        uint256 netAmount = 1000;
        uint256 grossAmount = org.calculateGrossAmount(netAmount);
        uint256 calculatedFee = org.calculateFee(grossAmount);
        assertEq(grossAmount - calculatedFee, netAmount, "Net amount calculation should be accurate");
    }

    function testReentrancyProtection() public {
        // Create a malicious token that attempts reentrancy
        MaliciousToken malToken = new MaliciousToken();
        factory.addToken("Malicious Token", address(malToken));
        
        // Create recipient
        org.createRecipient(recipient, "Test Recipient", 1000);
        
        // Fund the malicious token
        malToken.mint(address(this), 1000 ether);
        malToken.approve(address(org), type(uint256).max);
        
        // Set up the reentrancy attack
        malToken.setTarget(address(org), recipient);
        
        // Attempt reentrancy attack
        vm.expectRevert(CustomErrors.ReentrantCall.selector);
        org.disburseToken(address(malToken), recipient, 100);
    }

    function testAdvanceRepaymentScenarios() public {
        // Create recipient with salary and advance limit
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);
        
        // Request and approve advance
        vm.prank(recipient);
        org.requestAdvance(300, address(token));
        org.approveAdvance(recipient);
        
        // Verify advance state
        StructLib.Structs.Recipient memory recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.advanceCollected, 300, "Advance should be recorded");
        
        // Attempt to disburse less than advance amount
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.disburseToken(address(token), recipient, 200);
        
        // Disburse more than advance amount to trigger repayment
        org.disburseToken(address(token), recipient, 1000);
        
        // Verify advance is cleared
        recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.advanceCollected, 0, "Advance should be cleared after repayment");
        
        // Verify advance request is cleared
        (,,,,,bool repaid,) = org.advanceRequests(recipient);
        assertTrue(repaid, "Advance should be marked as repaid");
    }

    function testComplexBatchOperations() public {
        // Create multiple recipients with different scenarios
        address[] memory addresses = new address[](3);
        string[] memory names = new string[](3);
        uint256[] memory salaries = new uint256[](3);
        
        addresses[0] = address(10);
        addresses[1] = address(11);
        addresses[2] = address(12);
        names[0] = "Recipient 1";
        names[1] = "Recipient 2";
        names[2] = "Recipient 3";
        salaries[0] = 1000;
        salaries[1] = 2000;
        salaries[2] = 3000;
        
        org.batchCreateRecipients(addresses, names, salaries);
        
        // Set up advances for some recipients
        vm.prank(addresses[0]);
        org.requestAdvance(100, address(token));
        org.approveAdvance(addresses[0]);
        
        vm.prank(addresses[1]);
        org.requestAdvance(200, address(token));
        org.approveAdvance(addresses[1]);
        
        // Prepare disbursement amounts
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        
        recipients[0] = addresses[0];
        recipients[1] = addresses[1];
        recipients[2] = addresses[2];
        amounts[0] = 500;  // More than advance
        amounts[1] = 150;  // Less than advance
        amounts[2] = 1000; // No advance
        
        // Test batch disbursement with mixed scenarios
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.batchDisburseToken(address(token), recipients, amounts);
    }

    function testPermissions() public {
        address nonOwner = address(123);
        
        // Test owner-only functions
        vm.prank(nonOwner);
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        org.createRecipient(recipient, "Test", 1000);
        
        vm.prank(nonOwner);
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        org.disburseToken(address(token), recipient, 100);
        
        // Test factory-only functions
        vm.prank(nonOwner);
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        org.setTransactionFee(60);
        
        vm.prank(nonOwner);
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        org.setFeeCollector(address(456));
    }

    function testUpdateRecipientSalary() public {
        // Create recipient
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Store initial timestamp
        StructLib.Structs.Recipient memory initial = org.getRecipient(recipient);

        // Advance time by 1 second
        vm.warp(block.timestamp + 1);

        // Update salary
        uint256 newSalary = 2000;
        org.updateRecipientSalary(recipient, newSalary);

        // Verify update
        StructLib.Structs.Recipient memory recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.salaryAmount, newSalary, "Salary should be updated");
        assertTrue(recipientInfo.updatedAt > recipientInfo.createdAt, "Updated timestamp should be greater");
    }

    function test_RevertWhen_UpdateRecipientSalaryWithZeroAmount() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.updateRecipientSalary(recipient, 0);
    }

    function test_RevertWhen_UpdateRecipientSalaryForNonExistentRecipient() public {
        vm.expectRevert(CustomErrors.RecipientNotFound.selector);
        org.updateRecipientSalary(address(999), 1000);
    }

    function testAdvanceRepaymentWithMultiplePayments() public {
        // Create recipient with salary and advance limit
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        // Request and approve advance
        vm.startPrank(recipient);
        org.requestAdvance(300, address(token));
        vm.stopPrank();
        org.approveAdvance(recipient);

        // Verify advance state
        StructLib.Structs.Recipient memory recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.advanceCollected, 300, "Advance should be recorded");

        // Make partial payment that doesn't cover advance
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.disburseToken(address(token), recipient, 200);

        // Make payment that exactly covers advance (should fail)
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.disburseToken(address(token), recipient, 300);

        // Make payment that covers advance plus extra
        org.disburseToken(address(token), recipient, 400);

        // Verify advance is cleared
        recipientInfo = org.getRecipient(recipient);
        assertEq(recipientInfo.advanceCollected, 0, "Advance should be cleared");

        // Verify advance request is cleared and marked as repaid
        (,,,,,bool repaid,) = org.advanceRequests(recipient);
        assertTrue(repaid, "Advance should be marked as repaid");
    }

    function testFeeCalculationPrecision() public {
        // Test with very small amounts
        uint256 smallAmount = 1;
        uint256 fee = org.calculateFee(smallAmount);
        assertEq(fee, 0, "Fee should be 0 for very small amounts");

        // Test with amount that would cause precision loss
        uint256 amount = 10001;  // This should result in a non-zero fee
        fee = org.calculateFee(amount);
        assertTrue(fee > 0, "Fee should be non-zero for larger amounts");

        // Test with maximum possible amount
        uint256 maxAmount = type(uint256).max / 10001; // Prevent overflow
        fee = org.calculateFee(maxAmount);
        assertTrue(fee > 0, "Fee should be calculated for large amounts");

        // Verify fee calculation precision
        uint256 netAmount = 1000;
        uint256 grossAmount = org.calculateGrossAmount(netAmount);
        fee = org.calculateFee(grossAmount);
        assertEq(grossAmount - fee, netAmount, "Fee calculation should be precise");
    }

    function testEventEmissions() public {
        // Test RecipientCreated event
        vm.recordLogs();
        bytes32 recipientId = org.createRecipient(recipient, "Test Recipient", 1000);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1, "Should emit one event");
        
        // Verify RecipientCreated event
        bytes32 expectedEventSig = keccak256("RecipientCreated(bytes32,address,string)");
        assertEq(entries[0].topics[0], expectedEventSig, "Event signature should match");
        assertEq(bytes32(entries[0].topics[1]), recipientId, "Recipient ID should match");
        assertEq(address(uint160(uint256(entries[0].topics[2]))), recipient, "Recipient address should match");

        // Test TokenDisbursed event
        vm.recordLogs();
        org.disburseToken(address(token), recipient, 100);

        entries = vm.getRecordedLogs();
        bool foundTokenDisbursedEvent = false;
        expectedEventSig = keccak256("TokenDisbursed(address,address,uint256)");
        
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedEventSig) {
                foundTokenDisbursedEvent = true;
                assertEq(address(uint160(uint256(entries[i].topics[1]))), address(token), "Token address should match");
                assertEq(address(uint160(uint256(entries[i].topics[2]))), recipient, "Recipient address should match");
                break;
            }
        }
        assertTrue(foundTokenDisbursedEvent, "Should emit TokenDisbursed event");
    }

    function testComplexStateTransitions() public {
        // Create recipient
        org.createRecipient(recipient, "Test Recipient", 1000);
        StructLib.Structs.Recipient memory initial = org.getRecipient(recipient);

        // Advance time by 1 second
        vm.warp(block.timestamp + 1);

        // Update name
        org.updateRecipient(recipient, "Updated Name");
        StructLib.Structs.Recipient memory afterNameUpdate = org.getRecipient(recipient);
        assertEq(afterNameUpdate.name, "Updated Name", "Name should be updated");
        assertTrue(afterNameUpdate.updatedAt > initial.createdAt, "Updated timestamp should be greater than created timestamp");

        // Advance time by another second
        vm.warp(block.timestamp + 1);

        // Update salary
        org.updateRecipientSalary(recipient, 2000);
        StructLib.Structs.Recipient memory afterSalaryUpdate = org.getRecipient(recipient);
        assertEq(afterSalaryUpdate.salaryAmount, 2000, "Salary should be updated");
        assertTrue(afterSalaryUpdate.updatedAt > initial.createdAt, "Updated timestamp should be greater than created timestamp");
    }

    function testZeroAddressChecks() public {
        // Test creating recipient with zero address
        vm.expectRevert(CustomErrors.InvalidAddress.selector);
        org.createRecipient(address(0), "Test Recipient", 1000);

        // Test batch create with zero address
        address[] memory addresses = new address[](2);
        string[] memory names = new string[](2);
        uint256[] memory salaries = new uint256[](2);
        addresses[0] = address(1);
        addresses[1] = address(0);  // Zero address
        names[0] = "Recipient 1";
        names[1] = "Recipient 2";
        salaries[0] = 1000;
        salaries[1] = 2000;

        vm.expectRevert(CustomErrors.InvalidAddress.selector);
        org.batchCreateRecipients(addresses, names, salaries);
    }

    function testEmptyArrayInputs() public {
        // Test batch operations with mismatched array lengths
        address[] memory addresses = new address[](1);
        string[] memory names = new string[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert(CustomErrors.InvalidInput.selector);
        org.batchCreateRecipients(addresses, names, amounts);

        // Test batch disburse with mismatched arrays
        vm.expectRevert(CustomErrors.InvalidInput.selector);
        org.batchDisburseToken(address(token), addresses, new uint256[](2));
    }

    function testMaximumArrayLength() public {
        // Test batch operations with reasonable array length
        uint256 length = 5;
        address[] memory addresses = new address[](length);
        string[] memory names = new string[](length);
        uint256[] memory salaries = new uint256[](length);

        for(uint i = 0; i < length; i++) {
            addresses[i] = address(uint160(i + 1));
            names[i] = "Test";
            salaries[i] = 1000;
        }

        // This should pass as it's a reasonable length
        org.batchCreateRecipients(addresses, names, salaries);

        // Verify recipients were created
        for(uint i = 0; i < length; i++) {
            StructLib.Structs.Recipient memory recipient = org.getRecipient(addresses[i]);
            assertTrue(recipient.recipientId != 0, "Recipient should exist");
        }
    }

    function testAdvanceRequestEdgeCases() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);

        // Test requesting advance with amount > salary
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.requestAdvance(1001, address(token));

        // Test requesting advance with amount = salary
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.requestAdvance(1000, address(token));

        // Test approving non-existent advance request
        vm.expectRevert(CustomErrors.InvalidRequest.selector);
        org.approveAdvance(address(999));

        // Test requesting advance with unsupported token
        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidToken.selector);
        org.requestAdvance(100, address(999));
    }

    function testRecipientNameValidation() public {
        // Test with valid name
        org.createRecipient(recipient, "Valid Name", 1000);
        StructLib.Structs.Recipient memory createdRecipient = org.getRecipient(recipient);
        assertTrue(createdRecipient.recipientId != 0, "Recipient should be created");

        // Test with empty name
        vm.expectRevert(CustomErrors.NameRequired.selector);
        org.createRecipient(address(123), "", 1000);

        // Test updating with empty name
        vm.expectRevert(CustomErrors.NameRequired.selector);
        org.updateRecipient(recipient, "");
    }

    function testDisbursementEdgeCases() public {
        org.createRecipient(recipient, "Test Recipient", 1000);

        // Test disbursement with zero amount
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.disburseToken(address(token), recipient, 0);

        // Test disbursement with unsupported token
        vm.expectRevert(CustomErrors.TokenNotSupported.selector);
        org.disburseToken(address(999), recipient, 100);

        // Test disbursement to non-existent recipient
        vm.expectRevert(CustomErrors.RecipientNotFound.selector);
        org.disburseToken(address(token), address(999), 100);

        // Test disbursement with zero address token
        vm.expectRevert(CustomErrors.InvalidAddress.selector);
        org.disburseToken(address(0), recipient, 100);
    }

    function testAdvanceLimitEdgeCases() public {
        // Test setting advance limit for non-existent recipient
        vm.expectRevert(CustomErrors.RecipientNotFound.selector);
        org.setRecipientAdvanceLimit(recipient, 1001);

        // Create recipient and test valid advance limit
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);
        
        // Test setting advance limit for zero address
        vm.expectRevert(CustomErrors.InvalidAddress.selector);
        org.setRecipientAdvanceLimit(address(0), 500);
    }

    function testTransactionFeeEdgeCases() public {
        // Test setting fee to maximum allowed value
        factory.updateOrganizationTransactionFee(owner, 80);
        assertEq(org.transactionFee(), 80, "Fee should be updated to maximum allowed");

        // Test setting fee to zero
        factory.updateOrganizationTransactionFee(owner, 0);
        assertEq(org.transactionFee(), 0, "Fee should be updated to zero");

        // Test fee calculation with zero fee
        uint256 amount = 1000;
        assertEq(org.calculateFee(amount), 0, "Fee should be zero when fee percentage is zero");
        assertEq(org.calculateGrossAmount(amount), amount, "Gross amount should equal net amount when fee is zero");
    }

    function testConstructorAndInitialState() public {
        // Test constructor parameters
        assertEq(factory.owner(), address(this), "Owner should be set correctly");
        assertEq(factory.feeCollector(), feeCollector, "Fee collector should be set correctly");

        // Test initial state
        assertGt(factory.getSupportedTokensCount(), 0, "Initial token count should be more than Zero");
        assertNotEq(factory.getOrganizationContract(address(this)), address(0), "org contract should not be zero");
    }

    function testDefaultAdvanceLimitOnDeployment() public {
        // Deploy a new organization contract with a different owner
        address newOwner = address(789);
        vm.prank(newOwner);
        address newOrgAddress = factory.createOrganization("New Org", "New Description");
        OrgContract.OrganizationContract newOrg = OrgContract.OrganizationContract(newOrgAddress);

        // Create a recipient to check if they get the default advance limit
        address newRecipient = address(123);
        vm.prank(newOwner);  // Only owner can create recipient
        newOrg.createRecipient(newRecipient, "Test Recipient", 1000);

        // Verify the default advance limit is 0.1 ether
        assertEq(newOrg.recipientAdvanceLimit(newRecipient), 0.1 ether, "Default advance limit should be 0.1 ether");

        // Verify we can request an advance up to this limit
        vm.startPrank(newRecipient);
        newOrg.requestAdvance(0.1 ether, address(token));
        vm.stopPrank();

        // Verify the request was accepted
        (address requestRecipient, uint256 requestAmount,,,,, address requestToken) = newOrg.advanceRequests(newRecipient);
        assertEq(requestRecipient, newRecipient, "Request recipient should match");
        assertEq(requestAmount, 0.1 ether, "Request amount should match default limit");
        assertEq(requestToken, address(token), "Request token should match");
    }
}

// Malicious token contract for testing reentrancy protection
contract MaliciousToken is MockERC20 {
    OrganizationContract private targetContract;
    address private targetRecipient;
    bool private reentrancyAttempted;
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (!reentrancyAttempted && msg.sender == address(targetContract)) {
            reentrancyAttempted = true;
            // Attempt reentrancy
            targetContract.disburseToken(address(this), targetRecipient, amount);
        }
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        
        return true;
    }
    
    function setTarget(address _contract, address _recipient) external {
        targetContract = OrganizationContract(_contract);
        targetRecipient = _recipient;
        reentrancyAttempted = false;
    }
}
