//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IERC20.sol";
import "../libraries/structs.sol";
import "../libraries/errors.sol";
import "./Tokens.sol";

/**
 * @title Organization
 * @dev Contract for managing recipients and disbursing tokens
 */
contract OrganizationContract {
    address public owner;
    address public factory;
    address public feeCollector;

    Structs.Organization public organizationInfo;
    Structs.Payment[] public paymentHistory;

    mapping(address => Structs.Recipient) public recipients;
    mapping(address => Structs.AdvanceRequest) public advanceRequests;
    mapping(address => uint256) public recipientAdvanceLimit;

    uint256 public recipientCount;
    uint256 public advanceRequestCount;
    uint256 public defaultAdvanceLimit;
    uint256 public transactionFee;

    // Reentrancy guard state variable
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // Events
    event RecipientCreated(bytes32 indexed recipientId, address indexed walletAddress, string name);
    event RecipientUpdated(bytes32 indexed recipientId, address indexed walletAddress, string name);
    event TokenDisbursed(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event BatchDisbursement(address indexed tokenAddress, uint256 recipientCount, uint256 totalAmount);
    event AdvanceRequested(address indexed recipient, uint256 amount);
    event AdvanceApproved(address indexed recipient);
    event AdvanceRepaid(address indexed recipient, uint256 amount);
    event AdvanceLimitSet(address indexed recipient, uint256 amount);
    event DefaultAdvanceLimitSet(uint256 amount);
    event PayslipGenerated(address indexed recipient, uint256 indexed paymentId, string uri);
    event TransactionFeeUpdated(uint256 newFee);
    event FeeCollectorUpdated(address newCollector);
    event OrganizationInfoUpdated(bytes32 indexed organizationId, string name, string description);

    /**
     * @dev Modifier to prevent reentrancy attacks
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        if (_status == _ENTERED) revert CustomErrors.ReentrantCall();

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered 
        _status = _NOT_ENTERED;
    }



    constructor(
        address _owner,
        address _factory,
        address _factoryFeeCollector,
        string memory _name,
        string memory _description
    ) {
        if (_owner == address(0)) revert CustomErrors.InvalidAddress();
        if (_factory == address(0)) revert CustomErrors.InvalidAddress();
        if (_factoryFeeCollector == address(0)) revert CustomErrors.InvalidAddress();
        if (bytes(_name).length == 0) revert CustomErrors.NameRequired();
        if (bytes(_description).length == 0) revert CustomErrors.DescriptionRequired();
        owner = _owner;
        factory = _factory;

        organizationInfo = Structs.Organization({
            organizationId: bytes32(keccak256(abi.encodePacked(_owner, block.timestamp))),
            name: _name,
            description: _description,
            owner: _owner,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        transactionFee = 50;
        feeCollector = _factoryFeeCollector;
        defaultAdvanceLimit = 0.1 ether;
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Sets the transaction fee
     * @param _fee New fee in basis points (e.g., 50 = 0.5%)
     */
    function setTransactionFee(uint256 _fee) external {
        _onlyFactory();
        if (_fee > 80) revert CustomErrors.InvalidFee();
        transactionFee = _fee;
        emit TransactionFeeUpdated(_fee);
    }

    /**
     * @dev Sets the fee collector address
     * @param _collector New fee collector address
     */
    function setFeeCollector(address _collector) external {
        _onlyFactory();
        if (_collector == address(0)) revert CustomErrors.InvalidAddress();
        feeCollector = _collector;
        emit FeeCollectorUpdated(_collector);
    }

    /**
     * @dev Creates a new recipient
     * @param _address Wallet address of the recipient
     * @param _name Name of the recipient
     * @return ID of the created recipient
     */
    function createRecipient(address _address, string memory _name, uint256 _salaryAmount) public returns (bytes32) {
        _onlyOwner();
        if (bytes(_name).length == 0) revert CustomErrors.NameRequired();
        if (_address == address(0)) revert CustomErrors.InvalidAddress();
        if (recipients[_address].recipientId != 0) revert CustomErrors.RecipientAlreadyExists();

        bytes32 recipientId = bytes32(keccak256(abi.encodePacked(_address, block.timestamp)));

        Structs.Recipient memory newRecipient = Structs.Recipient({
            recipientId: recipientId,
            organizationId: organizationInfo.organizationId,
            name: _name,
            salaryAmount: _salaryAmount,
            advanceCollected: 0,
            walletAddress: _address,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        recipients[_address] = newRecipient;
        recipientCount++;

        recipientAdvanceLimit[_address] = defaultAdvanceLimit;

        emit RecipientCreated(recipientId, _address, _name);

        return recipientId;
    }

    /**
     * @dev Creates multiple recipients in a single transaction
     * @param _addresses Array of wallet addresses
     * @param _names Array of names
     */
    function batchCreateRecipients(address[] memory _addresses, string[] memory _names, uint256[] memory _salaries)
        public
    {
        _onlyOwner();
        if (_addresses.length != _names.length) revert CustomErrors.InvalidInput();
        if (_addresses.length != _salaries.length) revert CustomErrors.InvalidInput();

        for (uint256 i = 0; i < _addresses.length; i++) {
            createRecipient(_addresses[i], _names[i], _salaries[i]);
        }
    }

    /**
     * @dev Calculates the fee for a given amount
     * @param _amount Amount to calculate fee for
     * @return Fee amount
     */
    function calculateFee(uint256 _amount) public view returns (uint256) {
        return (_amount * transactionFee) / 10000;
    }
    /**
     * @dev Calculates the gross amount for a given net amount
     * @param _netAmount Net amount to calculate gross amount for
     * @return Gross amount
     */
    function calculateGrossAmount(uint256 _netAmount) public view returns (uint256) {
    return (_netAmount * 10000) / (10000 - transactionFee);
}

    /**
     * @dev Disburses tokens to a single recipient
     * @param _tokenAddress Address of the token to disburse
     * @param _recipient Recipient address
     * @param _netAmount Amount to disburse
     * @return True if successful
     */
    function disburseToken(address _tokenAddress, address _recipient, uint256 _netAmount)
    public
    nonReentrant
    returns (bool)
{
    _onlyOwner();
    if (_tokenAddress == address(0)) revert CustomErrors.InvalidAddress();
    if (_recipient == address(0)) revert CustomErrors.InvalidAddress();
    if (_netAmount == 0) revert CustomErrors.InvalidAmount();
    if (!isTokenSupported(_tokenAddress)) revert CustomErrors.TokenNotSupported();
    Structs.Recipient storage recipient = recipients[_recipient];
    if (recipient.recipientId == 0) revert CustomErrors.RecipientNotFound();

    uint256 grossAmount = calculateGrossAmount(_netAmount);
    uint256 fee = calculateFee(grossAmount);
    uint256 amountAfterFee = grossAmount - fee;

    require(amountAfterFee == _netAmount, "Mismatch in fee calculation"); // optional safety

    // Log payment
    Structs.Payment memory payment = Structs.Payment({
        recipient: _recipient,
        tokenAddress: _tokenAddress,
        amount: amountAfterFee,
        timestamp: block.timestamp
    });
    paymentHistory.push(payment);

    IERC20 token = IERC20(_tokenAddress);
    if (token.balanceOf(msg.sender) < grossAmount) revert CustomErrors.InvalidAmount();
    if (token.allowance(msg.sender, address(this)) < grossAmount) revert CustomErrors.InvalidAllowance();

    uint256 transferAmount = _netAmount;

    if (recipient.advanceCollected > 0) {
        if (_netAmount <= recipient.advanceCollected) {
            revert CustomErrors.InvalidAmount();
        }
        transferAmount = _netAmount - recipient.advanceCollected;
        uint256 repaidAmount = recipient.advanceCollected;
        recipient.advanceCollected = 0;
        delete advanceRequests[_recipient];
        emit AdvanceRepaid(_recipient, repaidAmount);
    }

    bool success = token.transferFrom(msg.sender, _recipient, transferAmount);
    if (!success) revert CustomErrors.TransferFailed();

    if (fee > 0) {
        success = token.transferFrom(msg.sender, feeCollector, fee);
        if (!success) revert CustomErrors.TransferFailed();
    }

    emit TokenDisbursed(_tokenAddress, _recipient, _netAmount);
    return true;
}


    /**
     * @dev Disburses tokens to multiple recipients
     * @param _tokenAddress Address of the token to disburse
     * @param _recipients Array of recipient addresses
     * @param _netAmounts Array of amounts to disburse
     * @return True if successful
     */
    function batchDisburseToken(
    address _tokenAddress,
    address[] memory _recipients,
    uint256[] memory _netAmounts
)
    public
    nonReentrant
    returns (bool)
{
    _onlyOwner();
    if (_recipients.length != _netAmounts.length) revert CustomErrors.InvalidInput();
    if (_tokenAddress == address(0)) revert CustomErrors.InvalidAddress();
    if (!isTokenSupported(_tokenAddress)) revert CustomErrors.TokenNotSupported();

    uint256 totalGrossAmount = 0;
    uint256 totalFees = 0;
    uint256[] memory actualTransferAmounts = new uint256[](_recipients.length);

    for (uint256 i = 0; i < _recipients.length; i++) {
        if (_netAmounts[i] == 0) revert CustomErrors.InvalidAmount();
        if (_recipients[i] == address(0)) revert CustomErrors.InvalidAddress();
        Structs.Recipient storage recipient = recipients[_recipients[i]];
        if (recipient.recipientId == 0) revert CustomErrors.RecipientNotFound();

        uint256 grossAmount = calculateGrossAmount(_netAmounts[i]);
        uint256 fee = calculateFee(grossAmount);
        uint256 amountAfterFee = grossAmount - fee;

        require(amountAfterFee == _netAmounts[i], "Fee miscalculation");

        totalGrossAmount += grossAmount;
        totalFees += fee;

        // Check if this payment would cover any advance
        if (recipient.advanceCollected > 0) {
            if (_netAmounts[i] <= recipient.advanceCollected) {
                revert CustomErrors.InvalidAmount();
            }
            actualTransferAmounts[i] = _netAmounts[i] - recipient.advanceCollected;
        } else {
            actualTransferAmounts[i] = _netAmounts[i];
        }

        Structs.Payment memory payment = Structs.Payment({
            recipient: _recipients[i],
            tokenAddress: _tokenAddress,
            amount: _netAmounts[i],
            timestamp: block.timestamp
        });

        paymentHistory.push(payment);
    }

    IERC20 token = IERC20(_tokenAddress);
    if (token.balanceOf(msg.sender) < totalGrossAmount) revert CustomErrors.InvalidAmount();
    if (token.allowance(msg.sender, address(this)) < totalGrossAmount) revert CustomErrors.InvalidAllowance();

    for (uint256 i = 0; i < _recipients.length; i++) {
        address recipient = _recipients[i];

        // Repay advance if needed
        if (recipients[recipient].advanceCollected > 0) {
            uint256 repaidAmount = recipients[recipient].advanceCollected;
            recipients[recipient].advanceCollected = 0;
            advanceRequests[recipient].repaid = true;
            emit AdvanceRepaid(recipient, repaidAmount);
        }

        bool success = token.transferFrom(msg.sender, recipient, actualTransferAmounts[i]);
        if (!success) revert CustomErrors.TransferFailed();

        emit TokenDisbursed(_tokenAddress, recipient, _netAmounts[i]);
    }

    if (totalFees > 0) {
        bool success = token.transferFrom(msg.sender, feeCollector, totalFees);
        if (!success) revert CustomErrors.TransferFailed();
    }

    emit BatchDisbursement(_tokenAddress, _recipients.length, totalGrossAmount);
    return true;
}


    /**
     * @dev Returns information about a recipient
     * @param _address Recipient address
     * @return Recipient information
     */
    function getRecipient(address _address) public view returns (Structs.Recipient memory) {
        if (_address == address(0)) revert CustomErrors.InvalidAddress();
        if (recipients[_address].recipientId == bytes32(0)) revert CustomErrors.RecipientNotFound();
        return recipients[_address];
    }

    /**
     * @dev Updates recipient information
     * @param _address Recipient address
     * @param _name Name of the recipient
     */
    function updateRecipient(address _address, string memory _name) public {
        _onlyOwner();
        if (_address == address(0)) revert CustomErrors.InvalidAddress();
        if (recipients[_address].recipientId == 0) revert CustomErrors.RecipientNotFound();
        if (bytes(_name).length == 0) revert CustomErrors.NameRequired();

        Structs.Recipient storage recipient = recipients[_address];
        recipient.name = _name;
        recipient.updatedAt = block.timestamp;
    }

    /**
     * @dev Updates recipient salary amount
     * @param _address Recipient address
     * @param _salaryAmount New salary amount
     */
    function updateRecipientSalary(address _address, uint256 _salaryAmount) public {
        _onlyOwner();
        if (_address == address(0)) revert CustomErrors.InvalidAddress();
        if (recipients[_address].recipientId == 0) revert CustomErrors.RecipientNotFound();
        if (_salaryAmount == 0) revert CustomErrors.InvalidAmount();

        Structs.Recipient storage recipient = recipients[_address];
        recipient.salaryAmount = _salaryAmount;
        recipient.updatedAt = block.timestamp;
    }

    /**
     * @dev Returns the organization information
     * @return Organization information
     */
    function getOrganizationInfo() public view returns (Structs.Organization memory) {
        return organizationInfo;
    }

    /**
     * @dev Updates the organization information
     * @param _name Name of the organization
     * @param _description Description of the organization
     */
    function updateOrganizationInfo(string memory _name, string memory _description) public {
        _onlyOwner();
        if (bytes(_name).length == 0) revert CustomErrors.NameRequired();
        if (bytes(_description).length == 0) revert CustomErrors.DescriptionRequired();

        organizationInfo.name = _name;
        organizationInfo.description = _description;
        organizationInfo.updatedAt = block.timestamp;

        emit OrganizationInfoUpdated(organizationInfo.organizationId, _name, _description);
    }

    /**
     * @dev Sets the default advance limit for all new recipients
     * @param _limit New default advance limit
     */
    function setDefaultAdvanceLimit(uint256 _limit) public {
        _onlyOwner();
        defaultAdvanceLimit = _limit;
        emit DefaultAdvanceLimitSet(_limit);
    }

    /**
     * @dev Sets the advance limit for a specific recipient
     * @param _recipient Recipient address
     * @param _limit New advance limit
     */
    function setRecipientAdvanceLimit(address _recipient, uint256 _limit) public {
        _onlyOwner();
        if (_recipient == address(0)) revert CustomErrors.InvalidAddress();
        if (recipients[_recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();
        recipientAdvanceLimit[_recipient] = _limit;
        emit AdvanceLimitSet(_recipient, _limit);
    }

    /**
     * @dev Creates a new advance request
     * @param _amount Amount requested
     * @param _tokenAddress Token address for the advance
     */
    function requestAdvance(uint256 _amount, address _tokenAddress) public {
        if (recipients[msg.sender].recipientId == bytes32(0)) revert CustomErrors.RecipientNotFound();
        if (!isTokenSupported(_tokenAddress)) revert CustomErrors.InvalidToken();
        if (_amount == 0) revert CustomErrors.InvalidAmount();
        if (_amount > recipientAdvanceLimit[msg.sender]) revert CustomErrors.InvalidAmount();

        // Check for existing active advance request
        Structs.AdvanceRequest memory existingRequest = advanceRequests[msg.sender];
        if (existingRequest.recipient != address(0) && !existingRequest.repaid) {
            revert CustomErrors.InvalidRequest();
        }

        Structs.AdvanceRequest memory newRequest = Structs.AdvanceRequest({
            recipient: msg.sender,
            amount: _amount,
            requestDate: block.timestamp,
            approvalDate: 0,
            approved: false,
            repaid: false,
            tokenAddress: _tokenAddress
        });

        advanceRequests[msg.sender] = newRequest;
        advanceRequestCount++;

        emit AdvanceRequested(msg.sender, _amount);
    }

    /**
     * @dev Approves an advance request
     * @param _recipientAddress Recipient address to be approved advance
     * @return True if successful
     */
    function approveAdvance(address _recipientAddress) public nonReentrant returns (bool) {
        _onlyOwner();
        if (_recipientAddress == address(0)) revert CustomErrors.InvalidAddress();
        Structs.AdvanceRequest storage request = advanceRequests[_recipientAddress];
        if (request.recipient == address(0)) revert CustomErrors.InvalidRequest();
        if (request.approved) revert CustomErrors.AlreadyApproved();
        if (recipients[request.recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();

        request.approved = true;
        request.approvalDate = block.timestamp;

         // Update the recipient's advance collected
        recipients[_recipientAddress].advanceCollected += request.amount;

        IERC20 token = IERC20(request.tokenAddress);
        if (token.balanceOf(msg.sender) < request.amount) revert CustomErrors.InvalidAmount();
        if (token.allowance(msg.sender, address(this)) < request.amount) revert CustomErrors.InvalidAllowance();

        bool success = token.transferFrom(msg.sender, request.recipient, request.amount);
        if (!success) revert CustomErrors.TransferFailed();

        emit AdvanceApproved(_recipientAddress);
        return true;
    }

    /**
     * @dev Returns all payments history
     * @return Array of all payments
     */
    function getAllPayments() public view returns (Structs.Payment[] memory) {
        return paymentHistory;
    }

    /**
     * @dev Returns payments for a specific recipient
     * @param _recipient Recipient address
     * @return Array of payments
     */
    function getRecipientPayments(address _recipient) public view returns (Structs.Payment[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < paymentHistory.length; i++) {
            if (paymentHistory[i].recipient == _recipient) {
                count++;
            }
        }

        Structs.Payment[] memory result = new Structs.Payment[](count);
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < paymentHistory.length; i++) {
            if (paymentHistory[i].recipient == _recipient) {
                result[resultIndex] = paymentHistory[i];
                resultIndex++;
            }
        }

        return result;
    }

    /**
     * @dev Returns pending advance requests
     * @return Array of pending advance requests
     */
    function getPendingAdvanceRequests() public view returns (address[] memory) {
        _onlyOwner();
        uint256 count = 0;
        
        // Count pending requests
        for (uint256 i = 0; i < recipientCount; i++) {
            address recipient = address(uint160(i)); // This is just for iteration and needs to be replaced
            Structs.AdvanceRequest memory request = advanceRequests[recipient];
            if (request.recipient != address(0) && !request.approved && !request.repaid) {
                count++;
            }
        }
        
        address[] memory pendingRequests = new address[](count);
        uint256 index = 0;
        
        // Fill pending requests
        for (uint256 i = 0; i < recipientCount; i++) {
            address recipient = address(uint160(i)); // This is just for iteration and needs to be replaced
            Structs.AdvanceRequest memory request = advanceRequests[recipient];
            if (request.recipient != address(0) && !request.approved && !request.repaid) {
                pendingRequests[index] = request.recipient;
                index++;
            }
        }
        
        return pendingRequests;
    }

    /**
     * @dev Checks if a token is supported by the factory
     * @param _tokenAddress Token address
     * @return True if the token is supported
     */
    function isTokenSupported(address _tokenAddress) public view returns (bool) {
        TokenRegistry registry = TokenRegistry(factory);
        return registry.isTokenSupported(_tokenAddress);
    }
    /**
     * @dev Checks if the caller is the owner of the organization
     */

    function _onlyOwner() internal view {
        if (msg.sender != owner) revert CustomErrors.UnauthorizedAccess();
    }

    /**
     * @dev Checks if the caller is the factory deployer of the organization
     */
    function _onlyFactory() internal view {
        if (msg.sender != factory) revert CustomErrors.UnauthorizedAccess();
    }
}
