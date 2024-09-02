// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeploySCT} from "script/DeploySCT.s.sol";
import {StableCoinToken} from "src/StableCoinToken.sol";
import {SCTEngine} from "src/SCTEngine.sol";

contract StableCoinTokenTest is Test {
    StableCoinToken stableCoinToken;
    SCTEngine engine;
    address s_owner;

    address ZERO_ADDRESS = address(0);
    uint256 ZERO_AMOUNT = 0;
    uint256 DEFAULT_AMOUNT = 1;
    uint256 MORE_THAN_DEFAULT_AMOUNT = 2;

    function setUp() external {
        DeploySCT deployer = new DeploySCT();
        (stableCoinToken, engine, ) = deployer.run();
        s_owner = address(engine);
    }

    function testIfMintsWithNonZeroAmountAndNonZeroAddress() public {
        vm.prank(s_owner);
        stableCoinToken.mint(s_owner, DEFAULT_AMOUNT);

        assertEq(stableCoinToken.balanceOf(s_owner), DEFAULT_AMOUNT);
    }

    function testRevertsIfMintToAddressIsZero() public {
        vm.expectRevert(
            StableCoinToken.StableCoinToken__AddressCantBeZero.selector
        );
        vm.prank(s_owner);
        stableCoinToken.mint(ZERO_ADDRESS, DEFAULT_AMOUNT);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.expectRevert(
            StableCoinToken.StableCoinToken__AmountMustBeMoreThanZero.selector
        );
        vm.prank(s_owner);
        stableCoinToken.mint(s_owner, ZERO_AMOUNT);
    }

    function testIfBurnsAmountEqualToBalance() public {
        vm.prank(s_owner);
        stableCoinToken.mint(s_owner, DEFAULT_AMOUNT);

        vm.prank(s_owner);
        stableCoinToken.burn(DEFAULT_AMOUNT);
    }

    function testRevertsIfBurnsAmountIsZero() public {
        vm.expectRevert(
            StableCoinToken.StableCoinToken__AmountMustBeMoreThanZero.selector
        );
        vm.prank(s_owner);
        stableCoinToken.burn(ZERO_AMOUNT);
    }

    function testRevertsIfBurnsAmountIsMoreThanBalance() public {
        vm.prank(s_owner);
        stableCoinToken.mint(s_owner, DEFAULT_AMOUNT);

        vm.expectRevert(
            StableCoinToken
                .StableCoinToken__AmountToBurnIsLessThanBalance
                .selector
        );
        vm.prank(s_owner);
        stableCoinToken.burn(MORE_THAN_DEFAULT_AMOUNT);
    }
}
