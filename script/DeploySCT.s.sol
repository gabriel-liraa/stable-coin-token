// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {Script} from "lib/forge-std/src/Script.sol";
import {StableCoinToken} from "src/StableCoinToken.sol";
import {SCTEngine} from "src/SCTEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeploySCT is Script {
    address[] private s_priceFeeds;
    address[] private s_tokens;

    function run() external returns (StableCoinToken, SCTEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        s_priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        s_tokens = [weth, wbtc];

        vm.startBroadcast(deployerKey);
        StableCoinToken stableCoinToken = new StableCoinToken();
        SCTEngine sctEngine = new SCTEngine(
            s_tokens,
            s_priceFeeds,
            address(stableCoinToken)
        );

        stableCoinToken.transferOwnership(address(sctEngine));
        vm.stopBroadcast();
        return (stableCoinToken, sctEngine, config);
    }
}
