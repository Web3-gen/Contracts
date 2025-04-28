// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/Tokens.sol";
import "../src/libraries/errors.sol";

contract TokenTest is Test {
    // Events from TokenRegistry contract
    event TokenAdded(address indexed tokenAddress, string name);
    event TokenRemoved(address indexed tokenAddress);

    TokenRegistry public tokenRegistry;
    address public owner;
    address public token1;
    address public token2;

    function setUp() public {
        owner = address(this);
        token1 = address(1);
        token2 = address(2);

        tokenRegistry = new TokenRegistry();
    }

    function testInitialState() public {
        assertEq(tokenRegistry.supportedTokensCount(), 0, "Initial supported tokens count should be 0");
        assertEq(tokenRegistry.owner(), address(this), "Owner should be test contract");
    }

    function testAddToken() public {
        string memory tokenName = "Test Token";
        tokenRegistry.addToken(tokenName, token1);

        assertEq(tokenRegistry.supportedTokensCount(), 1, "Supported tokens count should increase");
        assertEq(tokenRegistry.getTokenName(token1), tokenName, "Token name should be set correctly");
        assertTrue(tokenRegistry.isTokenSupported(token1), "Token should be supported");
    }

    function testRemoveToken() public {
        string memory tokenName = "Test Token";
        tokenRegistry.addToken(tokenName, token1);
        tokenRegistry.removeToken(token1);

        assertEq(tokenRegistry.supportedTokensCount(), 0, "Supported tokens count should decrease");
        assertEq(bytes(tokenRegistry.getTokenName(token1)).length, 0, "Token name should be removed");
        assertFalse(tokenRegistry.isTokenSupported(token1), "Token should not be supported");
    }

    function test_RevertWhen_AddTokenWithEmptyName() public {
        vm.expectRevert(CustomErrors.InvalidTokenName.selector);
        tokenRegistry.addToken("", token1);
    }

    function test_RevertWhen_AddTokenWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        tokenRegistry.addToken("Test Token", address(0));
    }

    function test_RevertWhen_AddExistingToken() public {
        string memory tokenName = "Test Token";
        tokenRegistry.addToken(tokenName, token1);

        vm.expectRevert(CustomErrors.TokenAlreadySupported.selector);
        tokenRegistry.addToken(tokenName, token1);
    }

    function test_RevertWhen_RemoveNonExistentToken() public {
        vm.expectRevert(CustomErrors.InvalidToken.selector);
        tokenRegistry.removeToken(token1);
    }

    function test_RevertWhen_RemoveTokenWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        tokenRegistry.removeToken(address(0));
    }

    function test_RevertWhen_GetTokenNameWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        tokenRegistry.getTokenName(address(0));
    }

    function test_RevertWhen_IsTokenSupportedWithZeroAddress() public {
        vm.expectRevert(CustomErrors.InvalidTokenAddress.selector);
        tokenRegistry.isTokenSupported(address(0));
    }

    function testMultipleTokenManagement() public {
        // Add multiple tokens
        tokenRegistry.addToken("Token 1", token1);
        tokenRegistry.addToken("Token 2", token2);
        
        assertEq(tokenRegistry.supportedTokensCount(), 2, "Should have two supported tokens");
        assertTrue(tokenRegistry.isTokenSupported(token1), "Token1 should be supported");
        assertTrue(tokenRegistry.isTokenSupported(token2), "Token2 should be supported");
        
        // Remove one token
        tokenRegistry.removeToken(token1);
        
        assertEq(tokenRegistry.supportedTokensCount(), 1, "Should have one supported token");
        assertFalse(tokenRegistry.isTokenSupported(token1), "Token1 should not be supported");
        assertTrue(tokenRegistry.isTokenSupported(token2), "Token2 should still be supported");
    }

    function test_RevertWhen_UnauthorizedAccess() public {
        address nonOwner = address(123);
        
        vm.startPrank(nonOwner);
        
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        tokenRegistry.addToken("Test Token", token1);
        
        vm.expectRevert(CustomErrors.UnauthorizedAccess.selector);
        tokenRegistry.removeToken(token1);
        
        vm.stopPrank();
    }

    function testTokenEvents() public {
        string memory tokenName = "Test Token";
        
        vm.expectEmit(true, false, false, true);
        emit TokenAdded(token1, tokenName);
        tokenRegistry.addToken(tokenName, token1);
        
        vm.expectEmit(true, false, false, false);
        emit TokenRemoved(token1);
        tokenRegistry.removeToken(token1);
    }
}
