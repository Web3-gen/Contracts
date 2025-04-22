// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title TokenRegistry
 * @dev Manages the registry of supported tokens for payments
 */
contract TokenRegistry {
    mapping(address => string) public supportedTokens;
    uint256 public supportedTokensCount;

    event TokenAdded(address indexed tokenAddress, string name);
    event TokenRemoved(address indexed tokenAddress);

    /**
     * @dev Adds a new token to the supported tokens list
     * @param _tokenName Name of the token
     * @param _tokenAddress Address of the token contract
     */
    function addToken(string memory _tokenName, address _tokenAddress) public virtual {
        require(bytes(_tokenName).length > 0, "Token name is required");
        require(_tokenAddress != address(0), "Invalid token address");
        require(bytes(supportedTokens[_tokenAddress]).length == 0, "Token already exists");

        supportedTokens[_tokenAddress] = _tokenName;
        supportedTokensCount++;

        emit TokenAdded(_tokenAddress, _tokenName);
    }

    /**
     * @dev Retrieves the name of a token
     * @param _tokenAddress Address of the token
     * @return Token name
     */
    function getTokenName(address _tokenAddress) public view returns (string memory) {
        require(_tokenAddress != address(0), "Invalid token address");
        return supportedTokens[_tokenAddress];
    }

    /**
     * @dev Removes a token from the supported tokens list
     * @param _tokenAddress Address of the token to remove
     */
    function removeToken(address _tokenAddress) public virtual {
        require(_tokenAddress != address(0), "Invalid token address");
        require(bytes(supportedTokens[_tokenAddress]).length > 0, "Token does not exist");

        delete supportedTokens[_tokenAddress];
        supportedTokensCount--;

        emit TokenRemoved(_tokenAddress);
    }

    /**
     * @dev Checks if a token is supported
     * @param _tokenAddress Address of the token to check
     * @return True if the token is supported, false otherwise
     */
    function isTokenSupported(address _tokenAddress) public view returns (bool) {
        require(_tokenAddress != address(0), "Invalid token address");
        return bytes(supportedTokens[_tokenAddress]).length > 0;
    }

    /**
     * @dev Returns the number of supported tokens
     * @return Number of supported tokens
     */
    function getSupportedTokensCount() public view returns (uint256) {
        return supportedTokensCount;
    }
}
