// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    DSCEngine dscEngine;
    address weth;
    address btc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    modifier depositedWethCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function setUp() external {
        deployer = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, btc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public view {
        // 15e18 * 3,000/ETH = 45,000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 45000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 300 ether;
        uint256 expectedWeth = 0.1 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////
    // mint Tests //
    /////////////////////////////

    function testMintRevertsIfHealthFactorIsToolow() public depositedWethCollateral {
        //user deposits 10 WETH = $30k
        //user tries to mint $15.1k DSC

        vm.expectRevert();
        vm.prank(USER);
        dscEngine.mint(15100 ether);
    }

    function testUserIsAbleToMintWithAHighEnoughHealthFactor() public depositedWethCollateral {
        //user deposits 10 WETH = $30k
        //user tries to mint $15k DSC

        vm.prank(USER);
        dscEngine.mint(15000 ether);

        assertEq(dsc.balanceOf(USER), 15000 ether);
    }

    /////////////////////////////
    // burn Tests //////////////
    /////////////////////////////

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function testRevertsIfCollateralDepositedIsZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        //user tries to mint more than his avail collat
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        vm.prank(USER);
        dscEngine.depositCollateral(weth, 0);
    }

    /////////////////////////////
    // redeemCollateral Tests ///
    /////////////////////////////

    function testRedeemCollateralRevertsIfAmountExceedsUsersBalance() public depositedWethCollateral {
        //user deposits 10 weth
        //user tries to redeem 11 weth

        vm.expectRevert();
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, 11 ether);
    }

    function testCanRedeemCollateralIfHealthFactorIsOkay() public depositedWethCollateral {
        //user deposits 10 weth
        //user tries to redeem 10 weth
        uint256 startingBalance = ERC20Mock(weth).balanceOf(USER);
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, 10 ether);

        uint256 endingBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(endingBalance, startingBalance + 10 ether);
    }

    //////////////////////////////////////
    // getAccountCollateralValue Tests ///
    //////////////////////////////////////

    function testGetAccountCollateralValueReturnsCorrectValue() public depositedWethCollateral {
        //user deposits 10 weth($30k)
        uint256 expectedUsdValue = 30000 ether;

        vm.prank(USER);
        uint256 value = dscEngine.getAccountCollateralValue(USER);
        console.log(value);
        assertEq(value, expectedUsdValue);
    }

    /////////////////////////
    // healthFactor Tests ///
    /////////////////////////

    function testHealthFactorReturnsInfinityWhenNoDSCIsMinted() public depositedWethCollateral {
        //user deposits 10 weth($30k)
        //user does not mint any DSC
        uint256 healthFactor;

        vm.prank(USER);
        healthFactor = dscEngine.getHealthFactor(USER);

        assertEq(healthFactor, type(uint256).max);
    }

    function testHealthFactorReturnsCorrectValueWhenSomeDSCIsMinted() public depositedWethCollateral {
        //user deposits 10 weth($30k)
        //user mints $7.5k worth of DSC
        //Health Factor should be 15k/7.5k -> 2
        uint256 expectedHealthFactor = 2 ether;
        uint256 actualHealthFactor;

        vm.startPrank(USER);
        dscEngine.mint(7500 ether);
        actualHealthFactor = dscEngine.getHealthFactor(USER);
        vm.stopPrank();

        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    ////////////////////////////////////////////////////////////
    // getAccountInformationReturnsCorrectInformation Tests ///
    ///////////////////////////////////////////////////////////

    function testGetAccountInformationReturnsCorrectInformation() public depositedWethCollateral {
        //user deposits 10 weth($30k)
        //user mints 0 DSC
        uint256 dscMinted;
        uint256 totalCollateralValue;

        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValue = 30000 ether;

        vm.prank(USER);
        (dscMinted, totalCollateralValue) = dscEngine.getAccountInformation(USER);
        assertEq(dscMinted, expectedDscMinted);
        assertEq(totalCollateralValue, expectedCollateralValue);
    }
}
