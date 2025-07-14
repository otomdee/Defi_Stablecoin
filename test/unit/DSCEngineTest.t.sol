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
    address ethUsdPriceFeed;

    address USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();

        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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
}
