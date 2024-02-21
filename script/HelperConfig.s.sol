// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct Config {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant BTC_PRICE = 1000e8;
    uint public constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    Config public config;

    constructor() {
        if (block.chainid == 11155111) {
            config = getSepoliaConfig();
        } else {
            config = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (Config memory) {
        return Config({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (Config memory) {
        if (config.wethUsdPriceFeed != address(0)) {
            return config;
        }

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        ERC20Mock weth = new ERC20Mock();
        weth.mint(msg.sender, 1000e8);
        ERC20Mock wbtc = new ERC20Mock();
        wbtc.mint(msg.sender, 1000e8);

        vm.stopBroadcast();

        return Config({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(weth),
            wbtc: address(wbtc),
            deployKey: ANVIL_KEY
        });
    }
}