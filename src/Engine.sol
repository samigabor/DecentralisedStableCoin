// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StableCoin} from "./StableCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title Engine
 * @author Sami Gabor
 *
 * The system is designed to be as minimal as possible and have the tokens maitain a peg to the USD.
 * This stablecoin has the following properties:
 * - Collateral: Exogenous (ETH & BTC)
 * - Minting: Algorithmic
 * - Relative Stability: Pegged to USD
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 *
 * DSC system should always be overcollateralized. At no point should the value of all collateral <= the $ backed value of all DSC.
 *
 * @notice This contract it the core of the stablecoin system. It is responsible for the minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO system. It is not meant to be a 1:1 copy, but rather a simplified version that is easier to understand.
 */
contract Engine {
    error Engine__ArrayLengthMismatch();
    error Engine__NotZeroAmount();
    error Engine__DepositCollateralFailed();
    error Engine__RedeemCollateralFailed();
    error Engine__HealthFactorBroken();
    error Engine__HealthFactorOk();
    error Engine__HealthFactorNotImproved();
    error Engine__MintFailed();
    error Engine__InvalidCollateral();

    event DepositCollateral(address indexed account, address indexed collateralAddress, uint256 collateralAmount);
    event RedeemCollateral(address indexed account, address indexed collateralAddress, uint256 collateralAmount);

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    address public immutable s_dsc;
    mapping(address => address) public s_priceFeeds;
    mapping(address => mapping(address => uint256)) public s_collateralDeposited;
    address[] public s_tokenCollateralAddresses;

    modifier onlyNonZeroAmount(uint256 amount) {
        if (amount == 0) revert Engine__NotZeroAmount();
        _;
    }

    modifier onlyAllowedToken(address collateralAddress) {
        if (s_priceFeeds[collateralAddress] == address(0)) revert Engine__InvalidCollateral();
        _;
    }

    constructor(address stablecoin, address[] memory tokenCollateralAddresses, address[] memory priceFeedAddresses) {
        s_dsc = stablecoin;

        if (tokenCollateralAddresses.length != priceFeedAddresses.length) revert Engine__ArrayLengthMismatch();
        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_priceFeeds[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
            s_tokenCollateralAddresses.push(tokenCollateralAddresses[i]);
        }
    }

    ////////////////////////////
    // External Functions     //
    ////////////////////////////

    /**
     * @notice Deposit collateral and mint DSC in one transaction
     * @param collateralAddress The address of the collateral to deposit
     * @param collateralAmount The amount of collateral to deposit
     * @param dscAmount The amount of DSC to mint
     */
    function depositCollateralAndMintDSC(address collateralAddress, uint256 collateralAmount, uint256 dscAmount)
        external
    {
        depositCollateral(collateralAddress, collateralAmount);
        mintDSC(dscAmount);
    }

    /**
     * @notice Redeem collateral and burn DSC in one transaction
     * @param collateralToken The address of the collateral to redeem
     * @param collateralAmount The amount of collateral to redeem
     * @param dscAmount The amount of DSC to burn
     */
    function redeemCollateralForDSC(address collateralToken, uint256 collateralAmount, uint256 dscAmount) external {
        burnDSC(dscAmount);
        redeemCollateral(collateralToken, collateralAmount);
    }

    function depositCollateral(address collateralAddress, uint256 collateralAmount)
        public
        onlyAllowedToken(collateralAddress)
        onlyNonZeroAmount(collateralAmount)
    {
        s_collateralDeposited[msg.sender][collateralAddress] += collateralAmount;
        emit DepositCollateral(msg.sender, collateralAddress, collateralAmount);

        bool success = IERC20(collateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) revert Engine__DepositCollateralFailed();
    }

    /**
     * @notice Liquidate a user's account if their health factor is below the threshold
     * @param user The address of the account to liquidate
     * @param collateralAddress The address of the collateral to liquidate
     * @notice Liquidator receives a bonus of 10% of the collateral value for watching the system and liquidating accounts
     */
    function liquidate(address user, address collateralAddress, uint256 debtToCover) external {
        uint256 liquidatorHealthFactorBefore = getHealthFactor(msg.sender);
        uint256 healthFactorBefore = getHealthFactor(user);
        if (healthFactorBefore >= MIN_HEALTH_FACTOR) revert Engine__HealthFactorOk();

        // We want to burn their DSC "debt" and take their collateral
        // bad user: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? of ETH
        // => 0.05 ETH
        uint256 tokenAmountFromDebtCovered = dscToTokenCollateral(collateralAddress, debtToCover);
        // Give the liquidator a 10% bonus (e.g. 0.005 ETH bonus for liquidating 100 DSC)
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateralAddress, totalCollateralToRedeem);
        _burnDSC(user, debtToCover);

        uint256 healthFactorAfter = getHealthFactor(user);
        if (healthFactorAfter <= healthFactorBefore) revert Engine__HealthFactorNotImproved();

        // sanity check to make sure liquidator's health factor was not affected
        uint256 liquidatorHealthFactorAfter = getHealthFactor(msg.sender);
        if (liquidatorHealthFactorAfter < liquidatorHealthFactorBefore) revert Engine__HealthFactorBroken();
    }

    function redeemCollateral(address collateralAddress, uint256 collateralAmount)
        public
        onlyAllowedToken(collateralAddress)
        onlyNonZeroAmount(collateralAmount)
    {
        _redeemCollateral(msg.sender, msg.sender, collateralAddress, collateralAmount);
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    function mintDSC(uint256 amount) public {
        bool minted = StableCoin(s_dsc).mint(msg.sender, amount);
        if (!minted) revert Engine__MintFailed();
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    function burnDSC(uint256 amount) public onlyNonZeroAmount(amount) {
        _burnDSC(msg.sender, amount);
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    //////////////////////////////////////
    // View Functions                   //
    //////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < s_tokenCollateralAddresses.length; i++) {
            address token = s_tokenCollateralAddresses[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValue += getUsdValue(token, amount);
        }
    }

    function getDscMinted(address user) public view returns (uint256) {
        return IERC20(s_dsc).balanceOf(user);
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(s_priceFeeds[token]).latestRoundData();
        return (uint256(price) * amount) / 1e8; // Chainlink returns 8 decimals
    }

    function dscToTokenCollateral(address token, uint256 amount) public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(s_priceFeeds[token]).latestRoundData();
        return (amount * 1e8) / uint256(price); // Chainlink returns 8 decimals
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_tokenCollateralAddresses;
    }

    /**
     * Returns how close to the liquidation a user is. If the return value is 1, the account is at the liquidation threshold.
     * For every 100 dsc minted there should exist at least 150 worth of collateral.
     * @param user The address of the account to check the health factor of
     * @return The health factor of the account
     */
    function getHealthFactor(address user) public view returns (uint256) {
        (uint256 dscBalance, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        if (dscBalance == 0) return collateralAdjustedForThreshold;

        return collateralAdjustedForThreshold * 1 ether / dscBalance;
    }

    function getAccountInformation(address user) public view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256){
        return s_collateralDeposited[user][token];
    }

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking the health factor being broken
     */
    function _burnDSC(address from, uint256 amount) internal {
        StableCoin(s_dsc).burn(from, amount); // TODO: is burnFrom needed in stablecoin contract, and not use ERC20 directly?
    }

    function _getAccountInformation(address user) internal view returns (uint256, uint256) {
        uint256 dscMinted = IERC20(s_dsc).balanceOf(user);
        uint256 collateralValueInUsd = getAccountCollateralValue(user);
        return (dscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorBelowThreshold(address user) internal view {
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) revert Engine__HealthFactorBroken();
    }

    function _redeemCollateral(address from, address to, address collateralAddress, uint256 collateralAmount)
        internal
    {
        s_collateralDeposited[from][collateralAddress] -= collateralAmount;
        emit RedeemCollateral(from, collateralAddress, collateralAmount);

        bool success = IERC20(collateralAddress).transfer(to, collateralAmount);
        if (!success) revert Engine__RedeemCollateralFailed();
    }
}
