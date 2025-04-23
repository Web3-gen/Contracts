// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/contracts/OrganizationFactory.sol";
import "../src/contracts/OrganizationContract.sol" as OrgContract;

contract OrganizationFactoryTest is Test {
    OrganizationFactory public factory;
    address public owner;
    address public user;
    address public token;

    function setUp() public {
        owner = address(this);
        user = address(1);
        token = address(2);
        
        factory = new OrganizationFactory();
    }

    function testCreateOrganization() public {
        string memory name = "Test Org";
        string memory description = "Test Description";
        
        address orgAddress = factory.createOrganization(name, description);
        assertTrue(orgAddress != address(0), "Organization address should not be zero");
        
        OrgContract.OrganizationContract org = OrgContract.OrganizationContract(orgAddress);
        assertEq(org.owner(), owner, "Owner should be set correctly");
    }

    function testAddToken() public {
        string memory tokenName = "Test Token";
        
        factory.addToken(tokenName, token);
        assertTrue(factory.isTokenSupported(token), "Token should be supported");
        assertEq(factory.getTokenName(token), tokenName, "Token name should be set correctly");
    }

    function testRemoveToken() public {
        string memory tokenName = "Test Token";
        
        factory.addToken(tokenName, token);
        factory.removeToken(token);
        
        assertFalse(factory.isTokenSupported(token), "Token should not be supported");
        assertEq(bytes(factory.getTokenName(token)).length, 0, "Token name should be removed");
    }

    function testGetSupportedTokensCount() public {
        assertEq(factory.getSupportedTokensCount(), 0, "Initial count should be 0");
        
        factory.addToken("Token 1", address(1));
        assertEq(factory.getSupportedTokensCount(), 1, "Count should increase after adding token");
        
        factory.addToken("Token 2", address(2));
        assertEq(factory.getSupportedTokensCount(), 2, "Count should increase after adding another token");
        
        factory.removeToken(address(1));
        assertEq(factory.getSupportedTokensCount(), 1, "Count should decrease after removing token");
    }

    function test_RevertWhen_CreateOrganizationWithEmptyName() public {
        vm.expectRevert();
        factory.createOrganization("", "Test Description");
    }

    function test_RevertWhen_CreateOrganizationWithEmptyDescription() public {
        vm.expectRevert();
        factory.createOrganization("Test Org", "");
    }

    function test_RevertWhen_AddTokenWithEmptyName() public {
        vm.expectRevert();
        factory.addToken("", token);
    }

    function test_RevertWhen_AddTokenWithZeroAddress() public {
        vm.expectRevert();
        factory.addToken("Test Token", address(0));
    }

    function test_RevertWhen_AddExistingToken() public {
        factory.addToken("Test Token", token);
        vm.expectRevert();
        factory.addToken("Test Token", token);
    }

    function test_RevertWhen_RemoveNonExistentToken() public {
        vm.expectRevert();
        factory.removeToken(token);
    }

    function test_RevertWhen_RemoveTokenWithZeroAddress() public {
        vm.expectRevert();
        factory.removeToken(address(0));
    }

    function test_RevertWhen_GetTokenNameWithZeroAddress() public {
        vm.expectRevert();
        factory.getTokenName(address(0));
    }

    function test_RevertWhen_IsTokenSupportedWithZeroAddress() public {
        vm.expectRevert();
        factory.isTokenSupported(address(0));
    }
} 