// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployStablecoin} from "../../script/DeployStablecoin.s.sol";
import {StableCoin} from "../../src/StableCoin.sol";
import {Engine} from "../../src/Engine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

/**
 * forge test --fork-url $RPC_URL
 */
contract EngineTest is Test {
    DeployStablecoin deployer;
    StableCoin stablecoin;
    Engine engine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    uint256 public constant COLLATERAL_DEPOSITED = 10 ether; // 10 eth
    uint256 public constant COLLATERAL_REDEEMED = 2 ether; // 2 eth
    uint256 public constant DSC_MINTED = 10000 ether; // $10,000
    uint256 public constant DSC_BURNED = 2000 ether; // $2,000
    uint256 public constant MIN_HEALTH_FACTOR = 1 ether;

    function setUp() public {
        deployer = new DeployStablecoin();
        (stablecoin, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed,weth, , ) = helperConfig.config();
    }

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, COLLATERAL_DEPOSITED);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_DEPOSITED);
        engine.depositCollateral(weth, COLLATERAL_DEPOSITED);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.startPrank(user);
        engine.mintDSC(DSC_MINTED);
        vm.stopPrank();
        _;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfCollateralAddressesIfDifferentThanPriceFeedAddresses() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(Engine.Engine__ArrayLengthMismatch.selector);
        new Engine(address(stablecoin), tokenAddresses, priceFeedAddresses);
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18;
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testDscToTokenCollateral() public {
        uint256 usdAmount = 100 ether; // $100
        uint256 expectedCollateralAmount = 0.05 ether; // 100 / 2000 = 0.05
        uint256 actualCollateralAmount = engine.dscToTokenCollateral(weth, usdAmount);
        assertEq(actualCollateralAmount, expectedCollateralAmount);
    }

    function testRevertWithInvalidCollateral() public {
        ERC20Mock invalidCollateral = new ERC20Mock();
        vm.startPrank(user);
        invalidCollateral.mint(user, COLLATERAL_DEPOSITED);
        vm.expectRevert(Engine.Engine__InvalidCollateral.selector);
        engine.depositCollateral(address(invalidCollateral), COLLATERAL_DEPOSITED);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedDscMinted = 0; // collateral deposited, but without minting any DSC
        uint256 expectedCollateralDeposited = engine.dscToTokenCollateral(weth, collateralValueInUsd);
        assertEq(dscMinted, expectedDscMinted);
        assertEq(COLLATERAL_DEPOSITED, expectedCollateralDeposited);
    }

    function testGetHealthFactor() public {
        assertEq(engine.getHealthFactor(user), type(uint256).max); // 0 collateral deposited, 0 DSC minted => health factor = max uint256

        uint256 collateralDeposited = 0.05 ether; // deposit $100 worth of collateral (100 / 2000 = 0.05)
        ERC20Mock(weth).mint(user, collateralDeposited);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), collateralDeposited);
        engine.depositCollateral(weth, collateralDeposited);
        vm.stopPrank();
        assertEq(engine.getHealthFactor(user), type(uint256).max); // collateral deposited, but 0 DSC minted => health factor = max uint256

        uint256 halfOfTheMaximumAmountAllowedToBeMinted = 25 ether;
        vm.prank(user);
        engine.mintDSC(halfOfTheMaximumAmountAllowedToBeMinted);
        assertEq(engine.getHealthFactor(user), 2 ether); // half of the maximum allowed DSC minted => health factor = 2

        vm.prank(user);
        engine.mintDSC(halfOfTheMaximumAmountAllowedToBeMinted);
        assertEq(engine.getHealthFactor(user), 1 ether); // maximum allowed DSC minted => health factor = 1
    }

    function testRevertsForZeroCollateralAmount() public {
        vm.startPrank(user);
        vm.expectRevert(Engine.Engine__NotZeroAmount.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositCollateral {
        uint256 initialCollateralValueInUsd = engine.getAccountCollateralValue(user);
        uint256 initialCollateral = initialCollateralValueInUsd / 2000; // 1 eth = $2000
        assertEq(initialCollateral, COLLATERAL_DEPOSITED);

        vm.startPrank(user);
        engine.redeemCollateral(weth, COLLATERAL_REDEEMED);
        uint256 collateralValueInUsd = engine.getAccountCollateralValue(user);
        vm.stopPrank();
        assertEq(collateralValueInUsd / 2000, COLLATERAL_DEPOSITED - COLLATERAL_REDEEMED);
    }

    function testDepositCollateralAndMintDSC() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, COLLATERAL_DEPOSITED);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_DEPOSITED);
        engine.depositCollateralAndMintDSC(weth, COLLATERAL_DEPOSITED, DSC_MINTED);
        vm.stopPrank();

        (uint256 dscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedDscMinted = DSC_MINTED;
        uint256 expectedCollateralDeposited = engine.dscToTokenCollateral(weth, collateralValueInUsd);
        assertEq(dscMinted, expectedDscMinted);
        assertEq(COLLATERAL_DEPOSITED, expectedCollateralDeposited);
    }

    function testBurnDSC() public depositCollateral mintDsc {
        uint256 dscAmount = engine.getDscMinted(user);
        assertEq(dscAmount, DSC_MINTED);
        vm.prank(user);
        engine.burnDSC(DSC_BURNED);

        uint256 dscAmountAfterBurn = engine.getDscMinted(user);
        assertEq(dscAmountAfterBurn, DSC_MINTED - DSC_BURNED);
    }

    function testRedeemCollateralForDSC() public depositCollateral mintDsc {

        uint256 ethPrice = engine.getUsdValue(weth, 1);
        uint256 collateralValue = engine.getAccountCollateralValue(user) / ethPrice;
        uint256 dscAmount = engine.getDscMinted(user);
        assertEq(collateralValue, COLLATERAL_DEPOSITED);
        assertEq(dscAmount, DSC_MINTED);
        vm.prank(user);
        // redeem 2 eth for 2000 DSC (burning less DSC would break the health factor)
        engine.redeemCollateralForDSC(weth, COLLATERAL_REDEEMED, DSC_BURNED);

        uint256 dscAmountAfterBurn = engine.getDscMinted(user);
        uint256 collateralValueAfterRedeem = engine.getAccountCollateralValue(user) / ethPrice;
        assertEq(dscAmountAfterBurn, DSC_MINTED - DSC_BURNED);
        assertEq(collateralValueAfterRedeem, COLLATERAL_DEPOSITED - COLLATERAL_REDEEMED);



        // redeeming any more collateral (without burning DSC) would break the health factor
        vm.prank(user);
        vm.expectRevert(Engine.Engine__HealthFactorBroken.selector);
        engine.redeemCollateral(weth, 1);
    }

    function testLiquidate() public depositCollateral mintDsc {
        uint256 healthFactor = engine.getHealthFactor(user);
        uint256 ethPrice = engine.getUsdValue(weth, 1);

        // user's health factor is greater or equal 1 => no liquidation
        vm.prank(user);
        vm.expectRevert(Engine.Engine__HealthFactorOk.selector);
        engine.liquidate(user, weth, DSC_MINTED);

        int256 newEthPrice = 1500e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newEthPrice);

        // liquidation amount is too small and it doesn't improve user's health factor => no liquidation
        vm.prank(user);
        vm.expectRevert(Engine.Engine__HealthFactorNotImproved.selector);
        engine.liquidate(user, weth, 1);
        
        // eth price drops from $2000 to $1500 => health factor is below 1 => liquidation
        engine.liquidate(user, weth, DSC_MINTED);

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2000e8);
    }

    /**
     * Collateral deposited: 10 ether
     * ETH price: $2000
     *  => Max DSC allowed to mint: 10000 DSC
     */
    function testGetMaxDSCAllowedToMint() public depositCollateral {
        uint256 maxDscAllowedToMint = engine.getMaxDSCAllowedToMint(user);
        assertEq(maxDscAllowedToMint, 10000 ether);

        vm.prank(user);
        engine.mintDSC(1000 ether);
        maxDscAllowedToMint = engine.getMaxDSCAllowedToMint(user);
        assertEq(maxDscAllowedToMint, 9000 ether);
    }
}
