// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/contracts/OrganizationContract.sol" as OrgContract;
import "../src/contracts/OrganizationFactory.sol";
import "../src/interfaces/IERC20.sol";
import "../src/libraries/structs.sol" as StructLib;

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Transfer to zero address");
        
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(to != address(0), "Transfer to zero address");
        
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "Approve to zero address");
        
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    // Helper function for testing
    function mint(address account, uint256 amount) external {
        require(account != address(0), "Mint to zero address");
        
        _balances[account] += amount;
        _totalSupply += amount;
    }
}

contract OrganizationContractTest is Test {
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
        
        factory = new OrganizationFactory();
        address orgAddress = factory.createOrganization("Test Org", "Test Description");
        org = OrgContract.OrganizationContract(orgAddress);
        
        token = new MockERC20();
        
        // Set up initial token balances
        token.mint(owner, 1000 ether);
        token.mint(user, 1000 ether);
        
        // Approve organization to spend tokens
        token.approve(address(org), type(uint256).max);

        // Set fee collector
        org.setFeeCollector(feeCollector);

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
    }

    function testRequestAdvance() public {
        // Create recipient first
        org.createRecipient(recipient, "Test Recipient", 1000);
        
        // Set advance limit
        org.setRecipientAdvanceLimit(recipient, 500);
        
        // Request advance
        uint256 amount = 300;
        uint256 repaymentDate = block.timestamp + 30 days;
        
        vm.prank(recipient);
        org.requestAdvance(amount, repaymentDate, address(token));
        
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
            uint256 expectedRepaymentDate,
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
        assertEq(expectedRepaymentDate, repaymentDate, "Repayment date mismatch");
        assertGt(approvalDate, requestDate, "Approval date should be after request date");
    }

    function testApproveAdvance() public {
        // Create recipient first
        org.createRecipient(recipient, "Test Recipient", 1000);
        
        // Set advance limit
        org.setRecipientAdvanceLimit(recipient, 500);
        
        // Request advance
        uint256 amount = 300;
        uint256 repaymentDate = block.timestamp + 30 days;
        
        vm.prank(recipient);
        org.requestAdvance(amount, repaymentDate, address(token));
        
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
        amounts[0] = 100;
        amounts[1] = 200;
        
        org.batchCreateRecipients(recipients, names, amounts);
        
        // Calculate total amount including fees
        uint256 totalAmount = amounts[0] + amounts[1];
        uint256 fee = (totalAmount * org.transactionFee()) / 10000;
        uint256 totalWithFees = totalAmount + fee;
        
        // Mint and approve tokens
        token.mint(owner, totalWithFees);
        token.approve(address(org), totalWithFees);
        
        // Disburse tokens
        bool success = org.batchDisburseToken(address(token), recipients, amounts);
        assertTrue(success, "Batch disbursement should succeed");
        
        // Check balances
        assertEq(token.balanceOf(recipients[0]), amounts[0], "Recipient 1 should receive correct amount");
        assertEq(token.balanceOf(recipients[1]), amounts[1], "Recipient 2 should receive correct amount");
        assertEq(token.balanceOf(feeCollector), fee, "Fee collector should receive correct fee");
    }

    function testSetTransactionFee() public {
        uint256 newFee = 30;
        org.setTransactionFee(newFee);
        assertEq(org.transactionFee(), newFee, "Transaction fee should be updated");
    }

    function testSetFeeCollector() public {
        address newCollector = address(4);
        org.setFeeCollector(newCollector);
        assertEq(org.feeCollector(), newCollector, "Fee collector should be updated");
    }

    function testSetRecipientAdvanceLimit() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        uint256 newLimit = 200;
        org.setRecipientAdvanceLimit(recipient, newLimit);
        assertEq(org.recipientAdvanceLimit(recipient), newLimit, "Advance limit should be updated");
    }

    function testAdvanceRepayment() public {
        // Create recipient and request advance
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);
        
        uint256 amount = 300;
        uint256 repaymentDate = block.timestamp + 30 days;
        
        vm.prank(recipient);
        org.requestAdvance(amount, repaymentDate, address(token));
        
        // Mint and approve tokens for advance
        token.mint(owner, amount);
        token.approve(address(org), amount);
        
        // Approve advance
        org.approveAdvance(recipient);
        
        // Mint and approve tokens for salary
        uint256 salary = 1000;
        uint256 fee = (salary * org.transactionFee()) / 10000;
        uint256 totalAmount = salary + fee;
        
        token.mint(owner, totalAmount);
        token.approve(address(org), totalAmount);
        
        // Disburse salary which should deduct the advance
        bool success = org.disburseToken(address(token), recipient, salary);
        assertTrue(success, "Disbursement should succeed");
        
        // Verify advance is marked as repaid
        (,,,,,,bool repaid,) = org.advanceRequests(recipient);
        assertTrue(repaid, "Advance should be marked as repaid");
        
        // Verify recipient received correct amount (salary - advance)
        assertEq(token.balanceOf(recipient), salary - amount, "Recipient should receive salary minus advance");
    }

    function test_RevertWhen_DisburseTokenWithUnpaidAdvance() public {
        org.createRecipient(recipient, "Test Recipient", 1000);
        org.setRecipientAdvanceLimit(recipient, 500);
        
        uint256 amount = 300;
        uint256 repaymentDate = block.timestamp + 30 days;
        
        vm.prank(recipient);
        org.requestAdvance(amount, repaymentDate, address(token));
        
        // Approve advance
        org.approveAdvance(recipient);
        
        // Ensure we have enough tokens for the disbursement but not enough to cover the advance
        token.mint(owner, amount - 1);
        token.approve(address(org), amount - 1);
        
        // Try to disburse less than the advance amount
        vm.expectRevert();
        org.disburseToken(address(token), recipient, amount - 1);
    }

    function test_RevertWhen_SetTransactionFeeTooHigh() public {
        vm.expectRevert("Fee too high");
        org.setTransactionFee(81);
    }

    function test_RevertWhen_SetFeeCollectorToZeroAddress() public {
        vm.expectRevert();
        org.setFeeCollector(address(0));
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
        org.requestAdvance(501, block.timestamp + 30 days, address(token));
    }

    function test_RevertWhen_ApproveAdvanceForNonExistentRecipient() public {
        vm.expectRevert();
        org.approveAdvance(recipient);
    }
} 