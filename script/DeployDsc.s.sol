// SPDX-License-Identifier: MIT

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

pragma solidity ^0.8.23;

contract DeployDsc is Script {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wEthUsdPriceFeed, address wBtcUsdPriceFeed, address wEth, address wBtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddresses = [wEth, wBtc];
        priceFeedAddresses = [wEthUsdPriceFeed, wBtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}
