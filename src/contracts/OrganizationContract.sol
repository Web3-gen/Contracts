//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
    Structs.Organization public organizationInfo;

    mapping(address => Structs.Recipient) public recipients;
    uint256 public recipientCount;

    Structs.Payment[] public paymentHistory;

    mapping(address => Structs.AdvanceRequest) public advanceRequests;
    uint256 public advanceRequestCount;
    mapping(address => uint256) public recipientAdvanceLimit;
    uint256 public defaultAdvanceLimit;

    uint256 public transactionFee;
    address public feeCollector;

    event RecipientCreated(bytes32 indexed recipientId, address indexed walletAddress, string name);
    event TokenDisbursed(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event BatchDisbursement(address indexed tokenAddress, uint256 recipientCount, uint256 totalAmount);
    event AdvanceRequested(address indexed recipient, uint256 amount);
    event AdvanceApproved(address indexed recipient);
    event AdvanceRepaid(uint256 indexed requestId);
    event PayslipGenerated(address indexed recipient, uint256 indexed paymentId, string uri);

    constructor(address _owner, string memory _name, string memory _description) {
        owner = _owner;
        factory = msg.sender;

        organizationInfo = Structs.Organization({
            organizationId: bytes32(keccak256(abi.encodePacked(_owner, block.timestamp))),
            name: _name,
            description: _description,
            owner: _owner,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        transactionFee = 50;
        feeCollector = _owner;
        defaultAdvanceLimit = 0.1 ether;
    }

    /**
     * @dev Sets the transaction fee
     * @param _fee New fee in basis points (e.g., 50 = 0.5%)
     */
    function setTransactionFee(uint256 _fee) external {
        _onlyOwner();
        require(_fee <= 80, "Fee too high");
        transactionFee = _fee;
    }

    /**
     * @dev Sets the fee collector address
     * @param _collector New fee collector address
     */
    function setFeeCollector(address _collector) external {
        _onlyOwner();
        if (_collector == address(0)) revert CustomErrors.InvalidAddress();
        feeCollector = _collector;
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
     * @dev Disburses tokens to a single recipient
     * @param _tokenAddress Address of the token to disburse
     * @param _recipient Recipient address
     * @param _amount Amount to disburse
     * @return True if successful
     */
    function disburseToken(address _tokenAddress, address _recipient, uint256 _amount) public returns (bool) {
        _onlyOwner();
        if (_tokenAddress == address(0)) revert CustomErrors.InvalidAddress();
        if (_recipient == address(0)) revert CustomErrors.InvalidAddress();
        if (_amount == 0) revert CustomErrors.InvalidAmount();
        if (!isTokenSupported(_tokenAddress)) revert CustomErrors.TokenNotSupported();
        if (recipients[_recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();

        uint256 fee = (_amount * transactionFee) / 10000;
        uint256 amountAfterFee = _amount + fee;

        Structs.Payment memory payment = Structs.Payment({
            recipient: _recipient,
            tokenAddress: _tokenAddress,
            amount: amountAfterFee,
            timestamp: block.timestamp
        });

        paymentHistory.push(payment);

        IERC20 token = IERC20(_tokenAddress);

        if (token.balanceOf(msg.sender) < amountAfterFee) revert CustomErrors.InvalidAmount();
        if (token.allowance(msg.sender, address(this)) < amountAfterFee) revert CustomErrors.InvalidAllowance();

        if (recipients[_recipient].advanceCollected > 0) {
            if (!token.transferFrom(msg.sender, _recipient, _amount - recipients[_recipient].advanceCollected)) {
                revert CustomErrors.TransferFailed();
            }
            // Mark advance as repaid
            advanceRequests[_recipient].repaid = true;
        } else {
            if (!token.transferFrom(msg.sender, _recipient, _amount)) {
                revert CustomErrors.TransferFailed();
            }
        }

        if (fee > 0) {
            if (!token.transferFrom(msg.sender, feeCollector, fee)) {
                revert CustomErrors.TransferFailed();
            }
        }

        recipients[_recipient].advanceCollected = 0;

        emit TokenDisbursed(_tokenAddress, _recipient, _amount);
        return true;
    }

    /**
     * @dev Disburses tokens to multiple recipients
     * @param _tokenAddress Address of the token to disburse
     * @param _recipients Array of recipient addresses
     * @param _amounts Array of amounts to disburse
     * @return True if successful
     */
    function batchDisburseToken(address _tokenAddress, address[] memory _recipients, uint256[] memory _amounts)
        public
        returns (bool)
    {
        _onlyOwner();
        if (_recipients.length != _amounts.length) revert CustomErrors.InvalidInput();

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (recipients[_recipients[i]].advanceCollected > 0) {
                if (_recipients[i] == address(0)) revert CustomErrors.InvalidAddress();
                if (!isTokenSupported(_tokenAddress)) revert CustomErrors.TokenNotSupported();
                if (_amounts[i] - recipients[_recipients[i]].advanceCollected == 0) revert CustomErrors.InvalidAmount();
                totalAmount += _amounts[i] - recipients[_recipients[i]].advanceCollected;
                continue;
            } else {
                if (_amounts[i] == 0) revert CustomErrors.InvalidAmount();
            }

            totalAmount += _amounts[i];
        }

        IERC20 token = IERC20(_tokenAddress);
        if (token.balanceOf(msg.sender) < totalAmount) revert CustomErrors.InvalidAmount();
        if (token.allowance(msg.sender, address(this)) < totalAmount) revert CustomErrors.InvalidAllowance();
        if (!token.transferFrom(msg.sender, address(this), totalAmount)) revert CustomErrors.TransferFailed();
        if (token.balanceOf(address(this)) < totalAmount) revert CustomErrors.TransferFailed();

        uint256 totalFees = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            uint256 amount = _amounts[i];

            if (recipients[recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();

            uint256 fee = (amount * transactionFee) / 10000;
            uint256 amountAfterFee = amount - fee;
            totalFees += fee;

            Structs.Payment memory payment = Structs.Payment({
                recipient: recipient,
                tokenAddress: _tokenAddress,
                amount: amountAfterFee,
                timestamp: block.timestamp
            });

            paymentHistory.push(payment);

            if (recipients[recipient].advanceCollected > 0) {
                if (!token.transfer(recipient, amount - recipients[recipient].advanceCollected)) {
                    revert CustomErrors.TransferFailed();
                }
            } else {
                if (!token.transfer(recipient, amount)) {
                    revert CustomErrors.TransferFailed();
                }
            }
            recipients[recipient].advanceCollected = 0;

            emit TokenDisbursed(_tokenAddress, recipient, amountAfterFee);
        }

        if (totalFees > 0) {
            if (!token.transfer(feeCollector, totalFees)) {
                revert CustomErrors.TransferFailed();
            }
        }

        emit BatchDisbursement(_tokenAddress, _recipients.length, totalAmount);
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
    }

    /**
     * @dev Sets the default advance limit for all new recipients
     * @param _limit New default advance limit
     */
    function setDefaultAdvanceLimit(uint256 _limit) public {
        _onlyOwner();
        defaultAdvanceLimit = _limit;
    }

    /**
     * @dev Sets the advance limit for a specific recipient
     * @param _recipient Recipient address
     * @param _limit New advance limit
     */
    function setRecipientAdvanceLimit(address _recipient, uint256 _limit) public {
        _onlyOwner();
        if (recipients[_recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();
        recipientAdvanceLimit[_recipient] = _limit;
    }

    /**
     * @dev Creates a new advance request
     * @param _amount Amount requested
     * @param _repaymentDate Expected repayment date
     * @param _tokenAddress Token address for the advance
     */
    function requestAdvance(uint256 _amount, uint256 _repaymentDate, address _tokenAddress) public {
        if (recipients[msg.sender].recipientId == bytes32(0)) revert CustomErrors.RecipientNotFound();
        if (_amount == 0) revert CustomErrors.InvalidAmount();
        if (_amount > recipientAdvanceLimit[msg.sender]) revert CustomErrors.InvalidAmount();
        if (_repaymentDate <= block.timestamp) revert CustomErrors.InvalidInput();

        Structs.AdvanceRequest memory newRequest = Structs.AdvanceRequest({
            recipient: msg.sender,
            amount: _amount,
            requestDate: block.timestamp,
            approvalDate: 0,
            repaymentDate: _repaymentDate,
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
    function approveAdvance(address _recipientAddress) public returns (bool) {
        _onlyOwner();
        if (_recipientAddress == address(0)) revert CustomErrors.InvalidAddress();
        Structs.AdvanceRequest storage request = advanceRequests[_recipientAddress];
        if (request.approved) revert CustomErrors.AlreadyApproved();
        if (recipients[request.recipient].recipientId == 0) revert CustomErrors.RecipientNotFound();

        request.approved = true;
        request.approvalDate = block.timestamp;

        IERC20 token = IERC20(request.tokenAddress);
        if (token.balanceOf(msg.sender) < request.amount) revert CustomErrors.InvalidAmount();

        if (!token.transferFrom(msg.sender, request.recipient, request.amount)) {
            revert CustomErrors.TransferFailed();
        }

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
}
