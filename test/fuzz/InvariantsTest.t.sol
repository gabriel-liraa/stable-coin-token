// SPDX-License-Identifier: MIT

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploySCT} from "script/DeploySCT.s.sol";
import {StableCoinToken} from "src/StableCoinToken.sol";
import {SCTEngine} from "src/SCTEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

pragma solidity ^0.8.25;

contract InvariantsTest is StdInvariant, Test {
    StableCoinToken stableCoinToken;
    SCTEngine engine;
    HelperConfig config;
    address USER = makeAddr("USER");
    address wethUsdPriceFeed;
    address weth;
    function setUp() external {
        DeploySCT deployer = new DeploySCT();
        (stableCoinToken, engine, config) = deployer.run();
        (wethUsdPriceFeed, , weth, , ) = config.activeNetworkConfig();
        targetContract(address(engine));
    }
}
