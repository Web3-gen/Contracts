//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
    address public owner;
    mapping(address => address) public organizationContracts;

    event OrganizationCreated(address indexed organizationAddress, address indexed owner, string name);

    function _onlyOwner() internal view {
        require(msg.sender == owner, "Not authorized");
    }

    constructor() {
        owner = msg.sender;
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

        OrganizationContract newOrganization = new OrganizationContract(msg.sender, _name, _description);
        organizationContracts[msg.sender] = address(newOrganization);

        emit OrganizationCreated(address(newOrganization), msg.sender, _name);

        return address(newOrganization);
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
}
