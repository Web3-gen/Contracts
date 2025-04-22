// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IERC20.sol";
import "./libraries/Structs.sol";
import "./libraries/CustomErrors.sol";

/**
 * @title OrganizationFactory
 * @dev Factory contract to create and manage organizations
 */
contract OrganizationFactory is TokenRegistry {
    address public owner;
    mapping(address => address) public organizationContracts;

    event OrganizationCreated(address indexed organizationAddress, address indexed owner, string name);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Creates a new organization contract
     * @param _name Organization name
     * @param _description Organization description
     * @param _website Organization website
     * @return Address of the newly created organization contract
     */
    function createOrganization(string memory _name, string memory _description, string memory _website)
        public
        returns (address)
    {
        require(bytes(_name).length > 0, CustomErrors.NameRequired());
        require(bytes(_description).length > 0, CustomErrors.DescriptionRequired());
        require(organizationContracts[msg.sender] == address(0), "Organization already exists for this address");

        // Create new organization contract
        Organization newOrg = new Organization(msg.sender, _name, _description, _website);

        // Store the organization contract address
        organizationContracts[msg.sender] = address(newOrg);

        emit OrganizationCreated(address(newOrg), msg.sender, _name);

        return address(newOrg);
    }

    /**
     * @dev Adds a token to the global registry (only owner can do this)
     * @param _tokenName Name of the token
     * @param _tokenAddress Address of the token contract
     */
    function addToken(string memory _tokenName, address _tokenAddress) public override onlyOwner {
        super.addToken(_tokenName, _tokenAddress);
    }

    /**
     * @dev Removes a token from the global registry (only owner can do this)
     * @param _tokenAddress Address of the token to remove
     */
    function removeToken(address _tokenAddress) public override onlyOwner {
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
