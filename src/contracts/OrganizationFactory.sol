//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/IERC20.sol";
import "../libraries/structs.sol";
import "../libraries/errors.sol";
import "./Tokens.sol";
import {OrganizationContract} from "./OrganizationContract.sol";

/**
 * @title OrganizationFactory
 * @dev Factory contract to create and manage organizations
 */
contract OrganizationFactory is TokenRegistry {
    address public feeCollector;

    mapping(address => address) public organizationContracts;
    mapping(address => Structs.Organization) public organizations;

    event OrganizationCreated(
        address indexed organizationAddress, address indexed owner, string name, string description, uint256 createdAt
    );

    constructor(address _feeCollector) {
        owner = msg.sender;
        feeCollector = _feeCollector;
    }

    /**
     * @dev Creates a new organization contract
     * @param _name Organization name
     * @param _description Organization description
     * @return Address of the newly created organization contract
     */
    function createOrganization(string memory _name, string memory _description) public returns (address) {
        if (bytes(_name).length == 0) revert CustomErrors.NameRequired();
        if (bytes(_description).length == 0) revert CustomErrors.DescriptionRequired();
        if (organizationContracts[msg.sender] != address(0)) revert CustomErrors.OrganizationAlreadyExists();

        OrganizationContract newOrganization =
            new OrganizationContract(msg.sender, address(this), feeCollector, _name, _description);
        address orgAddress = address(newOrganization);
        organizationContracts[msg.sender] = orgAddress;

        // Store organization details in the struct
        bytes32 orgId = bytes32(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
        organizations[msg.sender] = Structs.Organization({
            organizationId: orgId,
            name: _name,
            description: _description,
            owner: msg.sender,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit OrganizationCreated(orgAddress, msg.sender, _name, _description, block.timestamp);

        return orgAddress;
    }

    /**
     * @dev Gets organization details
     * @param _orgOwner Address of the organization owner
     * @return Organization details
     */
    function getOrganizationDetails(address _orgOwner) public view returns (Structs.Organization memory) {
        if (organizations[_orgOwner].organizationId == bytes32(0)) revert CustomErrors.OrganizationNotFound();
        return organizations[_orgOwner];
    }

    /**
     * @dev Adds a token to the global registry (only owner can do this)
     * @param _tokenName Name of the token
     * @param _tokenAddress Address of the token contract
     */
    function addToken(string memory _tokenName, address _tokenAddress) public override {
        _onlyOwner();
        super.addToken(_tokenName, _tokenAddress);
    }

    /**
     * @dev Removes a token from the global registry (only owner can do this)
     * @param _tokenAddress Address of the token to remove
     */
    function removeToken(address _tokenAddress) public override {
        _onlyOwner();
        if (_tokenAddress == address(0)) revert CustomErrors.InvalidToken();
        super.removeToken(_tokenAddress);
    }

    /**
     * @dev Gets the organization contract for a specific owner
     * @param _orgOwner Address of the organization owner
     * @return Organization contract address
     */
    function getOrganizationContract(address _orgOwner) public view returns (address) {
        return organizationContracts[_orgOwner];
    }

    /**
     * @dev Updates the transaction fee for an organization
     * @param _orgOwner Address of the organization owner
     * @param _newFee New fee in basis points (e.g., 50 = 0.5%)
     */
    function updateOrganizationTransactionFee(address _orgOwner, uint256 _newFee) public {
        _onlyOwner();
        address orgAddress = organizationContracts[_orgOwner];
        if (orgAddress == address(0)) revert CustomErrors.OrganizationNotFound();

        OrganizationContract org = OrganizationContract(orgAddress);
        org.setTransactionFee(_newFee);
    }

    /**
     * @dev Updates the fee collector for an organization
     * @param _orgOwner Address of the organization owner
     * @param _newCollector New fee collector address
     */
    function updateOrganizationFeeCollector(address _orgOwner, address _newCollector) public {
        _onlyOwner();
        address orgAddress = organizationContracts[_orgOwner];
        if (orgAddress == address(0)) revert CustomErrors.OrganizationNotFound();

        OrganizationContract org = OrganizationContract(orgAddress);
        org.setFeeCollector(_newCollector);
    }
}
