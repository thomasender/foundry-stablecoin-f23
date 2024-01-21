// SPDX-License-Identifer: MIT

pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10e18;
    uint256 public constant STARTING_TOKEN_BALANCE = 10e18;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public wEth;
    address public wBtc;
    uint256 public deployerKey;

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wEth, wBtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(wEth).mint(USER, STARTING_TOKEN_BALANCE);
    }

    /////////////////////////
    /// Price Tests /////////
    /////////////////////////

    function testGetUsdValue() public {
        uint256 wEthAmount = 15e18;
        // 15 * 2000 = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(wEth, wEthAmount);
        assertEq(actualUsd, expectedUsd);
    }

    ////////////////////////////////
    /// Deposit Collateral Tests ///
    ////////////////////////////////

    function testDepositCollateralRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(wEth, 0);
    }

    function testDepositCollateralRevertsIfTokenIsNotAllowed() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(makeAddr("notAllowed"), 1e18);
        vm.stopPrank();
    }
}
