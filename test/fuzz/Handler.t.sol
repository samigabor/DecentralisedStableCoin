// SPDX-License-Identifier: MIT

// Narrow down the way in which we call functions (e.g. don't waste rounds on calls which will always revert)

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Engine} from "../../src/Engine.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    uint256 public constant MAX_DEPOSIT_SIZE = 1000 ether;
    Engine dsce;
    StableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    address public user = makeAddr("user");

    constructor(Engine _dsce, StableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralAddressFromSeed(collateralSeed);
        uint256 collateralAmount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        collateral.approve(address(dsce), collateralAmount);
        dsce.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();

    }

    // Helper Functions
    function _getCollateralAddressFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        return collateralSeed % 2 == 0 ? weth : wbtc;
    }
}
