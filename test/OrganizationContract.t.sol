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
            totalFees -1 ,
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
        string memory newName = "Updated Org";
        string memory newDesc = "Updated Description";

        // Store initial timestamp
        StructLib.Structs.Organization memory initialInfo = org.getOrganizationInfo();

        // Advance time by 1 second
        vm.warp(block.timestamp + 1);

        org.updateOrganizationInfo(newName, newDesc);

        StructLib.Structs.Organization memory info = org.getOrganizationInfo();
        assertEq(info.name, newName, "Organization name should be updated");
        assertEq(info.description, newDesc, "Organization description should be updated");
        assertTrue(info.updatedAt > initialInfo.createdAt, "Updated timestamp should be greater than created timestamp");
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
        org.setRecipientAdvanceLimit(recipient, 500 ether);

        // First advance request
        vm.startPrank(recipient);
        org.requestAdvance(200 ether, address(token));

        // Should not be able to make another request before first is processed
        vm.expectRevert(CustomErrors.InvalidRequest.selector);
        org.requestAdvance(100 ether, address(token));
        vm.stopPrank();

        // Approve first advance
        uint256 advanceAmount = 200 ether;
        uint256 advanceGrossAmount = (advanceAmount * 10000) / (10000 - org.transactionFee());
        token.mint(owner, advanceGrossAmount);
        token.approve(address(org), advanceGrossAmount);
        org.approveAdvance(recipient);

        // Make salary payment to clear advance
        uint256 salaryNet = 1000 ether;
        uint256 salaryGross = (salaryNet * 10000) / (10000 - org.transactionFee());
        token.mint(owner, salaryGross);
        token.approve(address(org), salaryGross);
        org.disburseToken(address(token), recipient, salaryNet);

        // Should be able to request new advance after repayment
        vm.prank(recipient);
        org.requestAdvance(300 ether, address(token));
    }

    function testSetDefaultAdvanceLimit() public {
        uint256 newLimit = 1000 ether;
        org.setDefaultAdvanceLimit(newLimit);

        // Create new recipient and verify they get new default limit
        address newRecipient = address(6);
        org.createRecipient(newRecipient, "New Recipient", 2000);
        assertEq(org.recipientAdvanceLimit(newRecipient), newLimit, "New recipient should get default advance limit");
    }

    function test_RevertWhen_RequestZeroAdvance() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500 ether);

        vm.prank(recipient);
        vm.expectRevert(CustomErrors.InvalidAmount.selector);
        org.requestAdvance(0, address(token));
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
}
