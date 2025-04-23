// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/contracts/Tokens.sol";

contract TokenTest is Test {
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

    function testInitialState() public view {
        assertEq(tokenRegistry.supportedTokensCount(), 0, "Initial supported tokens count should be 0");
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
        vm.expectRevert("Token name is required");
        tokenRegistry.addToken("", token1);
    }

    function test_RevertWhen_AddTokenWithZeroAddress() public {
        vm.expectRevert("Invalid token address");
        tokenRegistry.addToken("Test Token", address(0));
    }

    function test_RevertWhen_AddExistingToken() public {
        string memory tokenName = "Test Token";
        tokenRegistry.addToken(tokenName, token1);

        vm.expectRevert("Token already exists");
        tokenRegistry.addToken(tokenName, token1);
    }

    function test_RevertWhen_RemoveNonExistentToken() public {
        vm.expectRevert("Token does not exist");
        tokenRegistry.removeToken(token1);
    }

    function test_RevertWhen_RemoveTokenWithZeroAddress() public {
        vm.expectRevert("Invalid token address");
        tokenRegistry.removeToken(address(0));
    }

    function test_RevertWhen_GetTokenNameWithZeroAddress() public {
        vm.expectRevert("Invalid token address");
        tokenRegistry.getTokenName(address(0));
    }

    function test_RevertWhen_IsTokenSupportedWithZeroAddress() public {
        vm.expectRevert("Invalid token address");
        tokenRegistry.isTokenSupported(address(0));
    }
}
