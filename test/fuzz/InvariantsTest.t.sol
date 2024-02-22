// SPDX-License-Identifier: MIT

// What are our invariants?
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {StableCoin} from "../../src/StableCoin.sol";
import {Engine} from "../../src/Engine.sol";
import {DeployStablecoin} from "../../script/DeployStablecoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Handler} from "./Handler.t.sol";

/*
* Invariants Test taret the Handler contract
*/
contract InvariantsTest is StdInvariant, Test {
    StableCoin stablecoin;
    Engine engine;
    address weth;
    address wbtc;

    Handler handler;

    address public user = makeAddr("user");

    function setUp() public {
        DeployStablecoin deployer = new DeployStablecoin();
        (stablecoin, engine,) = deployer.run();
        HelperConfig helperConfig = new HelperConfig();
        (,, weth, wbtc,) = helperConfig.config();
        handler = new Handler(engine, stablecoin);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the total value of collateral & the total supply of DSC
        // expect total value of collateral >= total supply of DSC
        uint256 wethCollateralAmount = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcCollateralAmount = IERC20(wbtc).balanceOf(address(engine));
        uint256 totalSupply = stablecoin.totalSupply();
        uint256 wethValue = engine.getUsdValue(weth, wethCollateralAmount);
        uint256 wbtcValue = engine.getUsdValue(wbtc, wbtcCollateralAmount);
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
