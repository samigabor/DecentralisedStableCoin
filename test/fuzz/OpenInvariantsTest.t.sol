// SPDX-License-Identifier: MIT

// What are our invariants?
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {Engine} from "../../src/Engine.sol";
import {DeployStablecoin} from "../../script/DeployStablecoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
* Open Invariants  are useless because random functions are called with totally random inputs which make no sense.
* e.g. redeem/liquidate before deposit, use random addresses for weth/wbtc, etc
* 
* Once fail_on_revert is switched on, the test will fail and without it the test is not very useful.
*/
contract OpenInvariantsTest is StdInvariant, Test {
    // get the total supply of DSC
    // get the total value of collateral
    // expect the total supply of DSC to be less than the total value of collateral

    StableCoin stablecoin;
    Engine engine;
    address weth;
    address wbtc;

    function setUp() public {
        DeployStablecoin deployer = new DeployStablecoin();
        (stablecoin, engine, ) = deployer.run();
        HelperConfig helperConfig = new HelperConfig();
        (, , weth, wbtc, ) = helperConfig.config();
        targetContract(address(engine));
    }

    function invariant_CollateralGreaterThanTotalDscMinted() public view {
        uint256 totalSupply = stablecoin.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));
        uint wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);
        assert(wethValue + wbtcValue >= totalSupply);
    }
}