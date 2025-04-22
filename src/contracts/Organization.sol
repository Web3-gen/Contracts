pragma solidity 0.8.28;

import "../interfaces/IERC20.sol";
import "../libraries/Structs.sol";
import "../libraries/errors.sol";

/**
 * @title Organization
 * @dev Contract for managing recipients and disbursing tokens
 */
contract Organization {
    address public owner;
    address public factory;
    Structs.Organization public organizationInfo;

    mapping(address => Structs.Recipient) public recipients;
    mapping(uint256 => address) public recipientAddresses;
    uint256 public recipientCount;

    Structs.Payment[] public paymentHistory;

    mapping(uint256 => Structs.AdvanceRequest) public advanceRequests;
    uint256 public advanceRequestCount;
    mapping(address => uint256) public recipientAdvanceLimit;
    uint256 public defaultAdvanceLimit;

    uint256 public immutable transactionFee;
    address public feeCollector;

    event RecipientCreated(uint256 indexed recipientId, address indexed walletAddress, string name);
    event TokenDisbursed(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event BatchDisbursement(address indexed tokenAddress, uint256 recipientCount, uint256 totalAmount);
    event AdvanceRequested(uint256 indexed requestId, address indexed recipient, uint256 amount);
    event AdvanceApproved(uint256 indexed requestId);
    event AdvanceRepaid(uint256 indexed requestId);
    event PayslipGenerated(address indexed recipient, uint256 indexed paymentId, string uri);

    modifier onlyOwner() {
        require(msg.sender == owner, CustomErrors.UnauthorizedAccess());
        _;
    }

    constructor(address _owner, string memory _name, string memory _description, string memory _website) {
        owner = _owner;
        factory = msg.sender;

        organizationInfo = Structs.Organization({
            organizationId: uint256(keccak256(abi.encodePacked(_owner, block.timestamp))),
            name: _name,
            description: _description,
            website: _website,
            owner: _owner,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        transactionFee = 50;
        feeCollector = _owner;
        defaultAdvanceLimit = 100 ether;
    }

    /**
     * @dev Sets the transaction fee
     * @param _fee New fee in basis points (e.g., 50 = 0.5%)
     */
    function setTransactionFee(uint256 _fee) external onlyOwner {
        require(_fee <= 80, "Fee too high");
        transactionFee = _fee;
    }

    /**
     * @dev Sets the fee collector address
     * @param _collector New fee collector address
     */
    function setFeeCollector(address _collector) external onlyOwner {
        require(_collector != address(0), CustomErrors.InvalidAddress());
        feeCollector = _collector;
    }

    /**
     * @dev Creates a new recipient
     * @param _address Wallet address of the recipient
     * @param _name Name of the recipient
     * @param _email Email of the recipient
     * @param _phone Phone number of the recipient
     * @param _addressLine1 Address line 1 of the recipient
     * @param _addressLine2 Address line 2 of the recipient
     * @param _city City of the recipient
     * @param _state State of the recipient
     * @param _country Country of the recipient
     * @return ID of the created recipient
     */
    function createRecipient(
        address _address,
        string memory _name,
        string memory _email,
        string memory _phone,
        string memory _addressLine1,
        string memory _addressLine2,
        string memory _city,
        string memory _state,
        string memory _country
    ) public onlyOwner returns (uint256) {
        require(bytes(_name).length > 0, CustomErrors.NameRequired());
        require(bytes(_email).length > 0, CustomErrors.EmailRequired());
        require(bytes(_phone).length > 0, CustomErrors.PhoneRequired());
        require(bytes(_addressLine1).length > 0, CustomErrors.AddressLine1Required());
        require(bytes(_city).length > 0, CustomErrors.CityRequired());
        require(bytes(_state).length > 0, CustomErrors.StateRequired());
        require(bytes(_country).length > 0, CustomErrors.CountryRequired());
        require(_address != address(0), CustomErrors.InvalidAddress());
        require(recipients[_address].recipientId == 0, CustomErrors.RecipientAlreadyExists());

        uint256 recipientId = uint256(keccak256(abi.encodePacked(_address, block.timestamp)));

        Structs.Recipient memory newRecipient = Structs.Recipient({
            recipientId: recipientId,
            organizationId: organizationInfo.organizationId,
            name: _name,
            email: _email,
            phone: _phone,
            addressLine1: _addressLine1,
            addressLine2: _addressLine2,
            city: _city,
            state: _state,
            country: _country,
            walletAddress: _address,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        recipients[_address] = newRecipient;
        recipientAddresses[recipientCount] = _address;
        recipientCount++;

        recipientAdvanceLimit[_address] = defaultAdvanceLimit;

        emit RecipientCreated(recipientId, _address, _name);

        return recipientId;
    }

    /**
     * @dev Creates multiple recipients in a single transaction
     * @param _addresses Array of wallet addresses
     * @param _names Array of names
     * @param _emails Array of emails
     * @param _phones Array of phone numbers
     * @param _addressLine1s Array of address line 1s
     * @param _addressLine2s Array of address line 2s
     * @param _cities Array of cities
     * @param _states Array of states
     * @param _countries Array of countries
     */
    function batchCreateRecipients(
        address[] memory _addresses,
        string[] memory _names,
        string[] memory _emails,
        string[] memory _phones,
        string[] memory _addressLine1s,
        string[] memory _addressLine2s,
        string[] memory _cities,
        string[] memory _states,
        string[] memory _countries
    ) public onlyOwner {
        require(_addresses.length == _names.length, CustomErrors.InvalidInput());
        require(_addresses.length == _emails.length, CustomErrors.InvalidInput());
        require(_addresses.length == _phones.length, CustomErrors.InvalidInput());
        require(_addresses.length == _addressLine1s.length, CustomErrors.InvalidInput());
        require(_addresses.length == _addressLine2s.length, CustomErrors.InvalidInput());
        require(_addresses.length == _cities.length, CustomErrors.InvalidInput());
        require(_addresses.length == _states.length, CustomErrors.InvalidInput());
        require(_addresses.length == _countries.length, CustomErrors.InvalidInput());

        for (uint256 i = 0; i < _addresses.length; i++) {
            createRecipient(
                _addresses[i],
                _names[i],
                _emails[i],
                _phones[i],
                _addressLine1s[i],
                _addressLine2s[i],
                _cities[i],
                _states[i],
                _countries[i]
            );
        }
    }

    /**
     * @dev Disburses tokens to a single recipient
     * @param _tokenAddress Address of the token to disburse
     * @param _recipient Recipient address
     * @param _amount Amount to disburse
     * @param _description Description/reason for the payment
     * @return True if successful
     */
    function disburseToken(address _tokenAddress, address _recipient, uint256 _amount, string memory _description)
        public
        onlyOwner
        returns (bool)
    {
        require(_tokenAddress != address(0), CustomErrors.InvalidAddress());
        require(_recipient != address(0), CustomErrors.InvalidAddress());
        require(_amount > 0, "Amount must be greater than 0");
        require(recipients[_recipient].recipientId != 0, CustomErrors.RecipientNotFound());

        uint256 fee = (_amount * transactionFee) / 10000;
        uint256 amountAfterFee = _amount - fee;

        Payment memory payment = Payment({
            recipient: _recipient,
            tokenAddress: _tokenAddress,
            amount: amountAfterFee,
            timestamp: block.timestamp,
            description: _description
        });

        paymentHistory.push(payment);

        IERC20 token = IERC20(_tokenAddress);

        require(token.balanceOf(msg.sender) >= _amount, "Insufficient token balance");

        token.approve(address(this), _amount);


        require(token.transferFrom(msg.sender, _recipient, amountAfterFee), "Token transfer to contract failed");

        if (fee > 0) {
            require(token.transferFrom(msg.sender, feeCollector, fee), "Fee transfer failed");
        }

        emit TokenDisbursed(_tokenAddress, _recipient, amountAfterFee);
        return true;
    }

    /**
     * @dev Disburses tokens to multiple recipients
     * @param _tokenAddress Address of the token to disburse
     * @param _recipients Array of recipient addresses
     * @param _amounts Array of amounts to disburse
     * @param _description Description/reason for the payments
     * @return True if successful
     */
    function batchDisburseToken(
        address _tokenAddress,
        address[] memory _recipients,
        uint256[] memory _amounts,
        string memory _description
    ) public onlyOwner returns (bool) {
        require(_recipients.length == _amounts.length, CustomErrors.InvalidInput());

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            totalAmount += _amounts[i];
        }

        IERC20 token = IERC20(_tokenAddress);
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient token balance");
        token.approve(address(this), totalAmount);
        require(token.transferFrom(msg.sender, address(this), totalAmount), "Token transfer to contract failed");
        require(token.balanceOf(address(this)) >= totalAmount, "Token transfer to contract failed");

        uint256 totalFees = 0;

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            uint256 amount = _amounts[i];

            require(recipients[recipient].recipientId != 0, CustomErrors.RecipientNotFound());

            uint256 fee = (amount * transactionFee) / 10000;
            uint256 amountAfterFee = amount - fee;
            totalFees += fee;

            Payment memory payment = Payment({
                recipient: recipient,
                tokenAddress: _tokenAddress,
                amount: amountAfterFee,
                timestamp: block.timestamp,
                description: _description
            });

            paymentHistory.push(payment);

            require(token.transfer(recipient, amountAfterFee), "Token transfer to recipient failed");

            emit TokenDisbursed(_tokenAddress, recipient, amountAfterFee);
        }

        if (totalFees > 0) {
            require(token.transfer(feeCollector, totalFees), "Fee transfer failed");
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
        require(_address != address(0), CustomErrors.InvalidAddress());
        require(recipients[_address].recipientId != 0, CustomErrors.RecipientNotFound());
        return recipients[_address];
    }

    /**
     * @dev Updates recipient information
     * @param _address Recipient address
     * @param _name Name of the recipient
     * @param _email Email of the recipient
     * @param _phone Phone number of the recipient
     * @param _addressLine1 Address line 1 of the recipient
     * @param _addressLine2 Address line 2 of the recipient
     * @param _city City of the recipient
     * @param _state State of the recipient
     * @param _country Country of the recipient
     */
    function updateRecipient(
        address _address,
        string memory _name,
        string memory _email,
        string memory _phone,
        string memory _addressLine1,
        string memory _addressLine2,
        string memory _city,
        string memory _state,
        string memory _country
    ) public onlyOwner {
        require(_address != address(0), CustomErrors.InvalidAddress());
        require(recipients[_address].recipientId != 0, CustomErrors.RecipientNotFound());
        require(bytes(_name).length > 0, CustomErrors.NameRequired());
        require(bytes(_email).length > 0, CustomErrors.EmailRequired());
        require(bytes(_phone).length > 0, CustomErrors.PhoneRequired());
        require(bytes(_addressLine1).length > 0, CustomErrors.AddressLine1Required());
        require(bytes(_city).length > 0, CustomErrors.CityRequired());
        require(bytes(_state).length > 0, CustomErrors.StateRequired());
        require(bytes(_country).length > 0, CustomErrors.CountryRequired());

        Structs.Recipient storage recipient = recipients[_address];
        recipient.name = _name;
        recipient.email = _email;
        recipient.phone = _phone;
        recipient.addressLine1 = _addressLine1;
        recipient.addressLine2 = _addressLine2;
        recipient.city = _city;
        recipient.state = _state;
        recipient.country = _country;
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
     * @param _website Website of the organization
     */
    function updateOrganizationInfo(string memory _name, string memory _description, string memory _website)
        public
        onlyOwner
    {
        require(bytes(_name).length > 0, CustomErrors.NameRequired());
        require(bytes(_description).length > 0, CustomErrors.DescriptionRequired());

        organizationInfo.name = _name;
        organizationInfo.description = _description;
        organizationInfo.website = _website;
        organizationInfo.updatedAt = block.timestamp;
    }

    /**
     * @dev Sets the default advance limit for all new recipients
     * @param _limit New default advance limit
     */
    function setDefaultAdvanceLimit(uint256 _limit) public onlyOwner {
        defaultAdvanceLimit = _limit;
    }

    /**
     * @dev Sets the advance limit for a specific recipient
     * @param _recipient Recipient address
     * @param _limit New advance limit
     */
    function setRecipientAdvanceLimit(address _recipient, uint256 _limit) public onlyOwner {
        require(recipients[_recipient].recipientId != 0, CustomErrors.RecipientNotFound());
        recipientAdvanceLimit[_recipient] = _limit;
    }

    /**
     * @dev Creates a new advance request
     * @param _amount Amount requested
     * @param _repaymentDate Expected repayment date
     * @param _tokenAddress Token address for the advance
     * @return Request ID
     */
    function requestAdvance(uint256 _amount, uint256 _repaymentDate, address _tokenAddress) public returns (uint256) {
        require(recipients[msg.sender].recipientId != 0, CustomErrors.RecipientNotFound());
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount <= recipientAdvanceLimit[msg.sender], "Amount exceeds advance limit");
        require(_repaymentDate > block.timestamp, "Repayment date must be in the future");

        uint256 requestId = advanceRequestCount;
        advanceRequestCount++;

        AdvanceRequest memory newRequest = AdvanceRequest({
            recipient: msg.sender,
            amount: _amount,
            requestDate: block.timestamp,
            approvalDate: 0,
            repaymentDate: _repaymentDate,
            approved: false,
            repaid: false,
            tokenAddress: _tokenAddress
        });

        advanceRequests[requestId] = newRequest;

        emit AdvanceRequested(requestId, msg.sender, _amount);

        return requestId;
    }

    /**
     * @dev Approves an advance request
     * @param _requestId Request ID
     * @return True if successful
     */
    function approveAdvance(uint256 _requestId) public onlyOwner returns (bool) {
        require(_requestId < advanceRequestCount, "Invalid request ID");
        AdvanceRequest storage request = advanceRequests[_requestId];
        require(!request.approved, "Already approved");
        require(recipients[request.recipient].recipientId != 0, CustomErrors.RecipientNotFound());

        request.approved = true;
        request.approvalDate = block.timestamp;

        IERC20 token = IERC20(request.tokenAddress);
        require(token.balanceOf(msg.sender) >= request.amount, "Insufficient token balance");

        require(token.transferFrom(msg.sender, request.recipient, request.amount), "Token transfer failed");

        emit AdvanceApproved(_requestId);

        return true;
    }

    /**
     * @dev Repays an advance
     * @param _requestId Request ID
     * @return True if successful
     */
    function repayAdvance(uint256 _requestId) public returns (bool) {
        require(_requestId < advanceRequestCount, "Invalid request ID");
        AdvanceRequest storage request = advanceRequests[_requestId];
        require(request.recipient == msg.sender, "Not your advance");
        require(request.approved, "Not approved");
        require(!request.repaid, "Already repaid");

        request.repaid = true;

        IERC20 token = IERC20(request.tokenAddress);
        require(token.balanceOf(msg.sender) >= request.amount, "Insufficient token balance");
        require(token.transferFrom(msg.sender, owner, request.amount), "Token transfer failed");

        emit AdvanceRepaid(_requestId);

        return true;
    }

    /**
     * @dev Returns all payments history
     * @return Array of all payments
     */
    function getAllPayments() public view returns (Payment[] memory) {
        return paymentHistory;
    }

    /**
     * @dev Returns payments for a specific recipient
     * @param _recipient Recipient address
     * @return Array of payments
     */
    function getRecipientPayments(address _recipient) public view returns (Payment[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < paymentHistory.length; i++) {
            if (paymentHistory[i].recipient == _recipient) {
                count++;
            }
        }

        Payment[] memory result = new Payment[](count);
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
}
