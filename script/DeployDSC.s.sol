// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig helperconfig;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        //deploy helperconfig
        helperconfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperconfig.getActiveConfig();
        //deploy contracts using config

        tokenAddresses = [config.weth, config.wbtc];
        priceFeedAddresses = [config.wethUsdPriceFeed, config.wbtcUsdPriceFeed];
        vm.startBroadcast();
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        //return contracts
        return (dsc, dscEngine, helperconfig);
    }
}
