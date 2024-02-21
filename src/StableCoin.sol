// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized StableCoin
 * @notice This is the contract meant to be governed by the Engine. This contract is just a simple ERC20 implementation of out stablecoin system.
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 */
contract StableCoin is ERC20, Ownable {
    error StableCoin__NotZeroAmount();
    error StableCoin__NotZeroAddress();
    error StableCoin__AmountExeedsBalance();

    constructor() ERC20("StableCoin", "USD") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount == 0) revert StableCoin__NotZeroAmount();
        if (to == address(0)) revert StableCoin__NotZeroAddress();
        
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyOwner {
        if (amount == 0) revert StableCoin__NotZeroAmount();
        if (amount > balanceOf(from)) revert StableCoin__AmountExeedsBalance();

        _burn(from, amount);
    }
}
