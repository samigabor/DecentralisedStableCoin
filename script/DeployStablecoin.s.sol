// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {StableCoin} from "../src/StableCoin.sol";
import {Engine} from "../src/Engine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployStablecoin is Script {
    address[] private tokenAddresses;
    address[] private priceFeedAddresses;

    function run() external returns (StableCoin stablecoin, Engine engine, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = helperConfig.config();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        
        vm.startBroadcast(deployerKey);
        stablecoin = new StableCoin();
        engine = new Engine(address(stablecoin), tokenAddresses, priceFeedAddresses);

        stablecoin.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (stablecoin, engine, helperConfig);
    }
}
