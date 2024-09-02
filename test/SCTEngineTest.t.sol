// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeploySCT} from "script/DeploySCT.s.sol";
import {StableCoinToken} from "src/StableCoinToken.sol";
import {SCTEngine} from "src/SCTEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract SCTEngineTest is Test {
    StableCoinToken stableCoinToken;
    SCTEngine engine;
    HelperConfig config;
    address USER = makeAddr("USER");
    address wethUsdPriceFeed;
    address weth;

    uint256 private constant ONE_ETH = 1e18;
    uint256 private constant DEPOSIT_VALUE = 1e18;
    uint256 private constant OK_TOKEN_AMOUNT_TO_MINT = 1000e18;
    uint256 private constant EXAGERATED_TOKEN_AMOUNT_TO_MINT = 1001e18;

    event CollateralDeposited(
        address indexed userAddress,
        address indexed collateralTokenAddress,
        uint256 indexed collateralAmount
    );

    event CollateralRedeemed(
        address indexed fromAddress,
        address indexed toAddress,
        address indexed collateralTokenAddress,
        uint256 collateralAmount
    );

    function setUp() external {
        DeploySCT deployer = new DeploySCT();
        (stableCoinToken, engine, config) = deployer.run();
        (wethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();
    }

    // Constructor

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testIfRevertsWhenTokenLengthIsNotEqualToPriceFeedLength() public {
        tokenAddresses.push(makeAddr("TOKEN"));
        priceFeedAddresses.push(makeAddr("PRICE_FEED_1"));
        priceFeedAddresses.push(makeAddr("PRICE_FEED_2"));
        vm.expectRevert(
            SCTEngine.SCTEngine__EachTokenMustHaveAPriceFeed.selector
        );
        new SCTEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(stableCoinToken)
        );
    }

    // DepositCollateral

    modifier depositOneEth() {
        ERC20Mock(weth).mint(USER, DEPOSIT_VALUE);
        ERC20Mock(weth).approveInternal(USER, address(engine), DEPOSIT_VALUE);
        vm.prank(USER);
        engine.depositCollateral(weth, DEPOSIT_VALUE);
        _;
    }

    modifier mintOneEth() {
        vm.prank(USER);
        engine.mintSct(OK_TOKEN_AMOUNT_TO_MINT);
        _;
    }

    function testDepositCollateral() public {
        ERC20Mock(weth).mint(USER, DEPOSIT_VALUE);
        ERC20Mock(weth).approveInternal(USER, address(engine), DEPOSIT_VALUE);
        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, address(weth), DEPOSIT_VALUE);
        vm.prank(USER);
        engine.depositCollateral(weth, DEPOSIT_VALUE);
    }

    function testDepositCollateralMapping() public depositOneEth {
        vm.prank(USER);
        assertEq(engine.getUserCollateralTokenBalance(weth), ONE_ETH);
    }

    function testDepositCollateralBalance() public depositOneEth {
        assertEq(IERC20(weth).balanceOf(USER), 0);
    }

    // MintSct

    function testMintSct() public depositOneEth {
        vm.prank(USER);
        engine.mintSct(OK_TOKEN_AMOUNT_TO_MINT);
    }

    function testMintSctRevertsIfBreaksTheHealthFactor() public depositOneEth {
        vm.expectRevert(SCTEngine.SCTEngine__HealthFactorBelowMinimum.selector);
        vm.prank(USER);
        engine.mintSct(EXAGERATED_TOKEN_AMOUNT_TO_MINT);
    }

    function testMintSctMapping() public depositOneEth {
        vm.prank(USER);
        engine.mintSct(OK_TOKEN_AMOUNT_TO_MINT);
        vm.prank(USER);
        assertEq(engine.getUserSCTBalance(), OK_TOKEN_AMOUNT_TO_MINT);
    }

    // RedeemCollateral

    function testRedeemCollateral() public depositOneEth {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, DEPOSIT_VALUE);
        vm.prank(USER);
        engine.redeemCollateral(weth, DEPOSIT_VALUE);
    }

    function testRedeemCollateralRevertsIfAmountIsGreaterThanDepositedCollateral()
        public
        depositOneEth
    {
        vm.expectRevert();
        vm.prank(USER);
        engine.redeemCollateral(weth, DEPOSIT_VALUE + 1);
    }

    function testRedeemCollateralMapping() public depositOneEth {
        vm.prank(USER);
        engine.redeemCollateral(weth, DEPOSIT_VALUE);
        assertEq(engine.getUserCollateralTokenBalance(weth), 0);
    }

    function testRedeemCollateralBalance() public depositOneEth {
        vm.prank(USER);
        engine.redeemCollateral(weth, DEPOSIT_VALUE);
        assertEq(IERC20(weth).balanceOf(USER), DEPOSIT_VALUE);
    }

    // BurnSct

    // function testBurnSct() public depositOneEth mintOneEth {
    //     // vm.startPrank(USER);
    //     vm.prank(USER);
    //     stableCoinToken.approve(address(engine), DEPOSIT_VALUE);
    //     uint256 allowance = stableCoinToken.allowance(USER, address(engine));
    //     console.log(allowance);
    //     console.log(address(engine));
    //     vm.prank(USER);
    //     engine.burnSct(DEPOSIT_VALUE);
    //     // vm.stopPrank();
    // }

    function testGetUsdValue() public view {
        uint256 expectedValue = 2000e18;
        uint256 wethPrice = uint256(engine.getCollateralUsdValue(weth, 1e18));
        assertEq(wethPrice, expectedValue);
    }
}
