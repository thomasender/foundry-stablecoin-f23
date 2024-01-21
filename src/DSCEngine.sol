// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 * @author Thomas Ender
 * The system is designed to be as minimal as possible.
 * The Token shall maintain their 1 Token = 1 USD value.
 * Exgeneous Collateral is used to back the system:
 *  - wETH
 *  - wBTC
 * Algorithmic Minting and Burning is used to maintain the value.
 *
 * It is similiar to DAI, but without governance and without fees
 * and uses only wETH and wBTC as collateral.
 *
 * This DSC System should always be overcollateralized.
 * At no point should the value of the collateral be less than the Dollar backed value of the minted DSC.
 *
 * @notice This contract is the core of the system and handles:
 * - minting DSC
 * - burning DSC
 * - depositing collateral
 * - redeeming collateral
 * @notice This contract is loosely based on the MakerDAO DSS (Dai Stablecoin System)
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////
    //////// Erros //////
    /////////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__DepositCollateral__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintingFailed();
    error DSCEngine__HealthFactorIntact();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    /// State Variables///
    //////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    // Ensure we are always overcollateralized
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    // Percentage of Bonus for Liquidators
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeed;
    /// Maps the user address to the amount of collateral deposited for each token
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscAmountMinted) private s_dscAmountMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private i_dsc;

    /////////////////////
    /// Events //////////
    /////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /////////////////////
    ////// Modifiers ///
    /////////////////////
    modifier mustBeMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////////////
    ///// Functions ////
    /////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (!(tokenAddresses.length == priceFeedAddresses.length)) {
            revert DSCEngine__TokenAddressesAndPriceFeedsLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    /// External Functions ///
    /////////////////////////

    /**
     *
     * @param tokenCollateralAddress the address of the token used as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
        mustBeMoreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        mustBeMoreThanZero(amountDscToMint)
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * follows Checks, Effects, Interactions pattern
     * @param tokenCollateralAddress the token used as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        mustBeMoreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__DepositCollateral__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress the collateral token to redeem
     * @param amountCollateral the amount collateral to redeem
     * @param amountDscToBurn the amount of usdc to burn
     * @notice This function burns DSC and redeems underyling collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redemmCollateral already checks if the health factor is broken
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        mustBeMoreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param dcsToMint the amount of DSC to mint
     * @notice follows CEI
     * @notice user needs more collateral than the min threshold
     * @notice this function is called by the user
     *
     */
    function mintDsc(uint256 dcsToMint) public mustBeMoreThanZero(dcsToMint) nonReentrant {
        s_dscAmountMinted[msg.sender] += dcsToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, dcsToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    function burnDsc(uint256 amountDscToBeBurned) public mustBeMoreThanZero(amountDscToBeBurned) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDscToBeBurned);
        // Likely not needed, but kept for now
        // This could be removed and optimize gas consumption
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateralToken the erc20 colleteral token to liquidate from the user
     * @param user the user with broken health factor, the health factor is below MIN_HEALTH_FACTOR
     * @param debtToCover the amount of debt to be covered
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This works because the protocol is overcollateralized at all times!
     * @notice A know bug would be if the protocoll is only 100% collateralized or even uncollateralized
     * Then we would not incentivise the liquidators.
     * For example, if the price of the collateral drops too much before the liquidator can liquidate the user.
     * Two examples:
     * One:
     *  A user has 1000 DSC and 100 wETH as collateral.
     *  The collateral is worth 2000 USD and the users health factor is still good.
     *  Then, the collateral USD value drops below the threshold and is only wort 1300 USD.
     *  The users healthfactor is now broken. A liquidator can now come in and liquidate the user
     *  for a bonus of 300 USD! They pay back the 1000 DSC debt of the user and cash out the wEth worth 1300 USD.
     *  Makes 300 USD profit for them for liquidating the user.
     *
     * Two:
     *  A user has 1000 DSC and 100 wETH as collateral.
     *  The collateral is worth 2000 USD and the users health factor is still good.
     *  Then, the collateral USD value drops way below the threshold and is only worth 950 USD.
     *  Now we have a problem, because the liquidator would not get any bonus for liquidating the user.
     *  This would cause the DSC to depeg from the USD. So 1 DSC would no longer be 1 USD.
     *
     * Follows CEI
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        mustBeMoreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIntact();
        }
        uint256 tokenAmountOfDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        uint256 bonusCollateral = (tokenAmountOfDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToBeRedeemed = tokenAmountOfDebtCovered + bonusCollateral;
        _redeemCollateral(collateralToken, totalCollateralToBeRedeemed, user, msg.sender);
        _burnDsc(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            // revert if the health factor of the user in concern did not improve
            revert DSCEngine__HealthFactorNotImproved();
        }
        // revert if the health factor of the liquidator is now broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    /// Private & Internal View Functions ///
    /////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_dscAmountMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     *
     * @param user the user to check the health factor for
     * @return healthFactor of the health factor of the user.
     * If the health factor is below 1, the users position can be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // 1. Check health factor: Do they have enough collateral?
    // 2. Revert if bad health factor
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__DepositCollateral__TransferFailed();
        }
    }

    /**
     * @dev low-level internal function, do not call unless function call it is checking for health factors being broken
     */
    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amountDscToBeBurned) private {
        s_dscAmountMinted[onBehalfOf] -= amountDscToBeBurned;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBeBurned);
        // hypothetically this revert will never happen
        // bc if the transerFrom fails, it will revert itself
        if (!success) {
            revert DSCEngine__DepositCollateral__TransferFailed();
        }
        i_dsc.burn(amountDscToBeBurned);
    }

    ////////////////////////////////////////
    /// Public & External View Functions ///
    ////////////////////////////////////////

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through collateral tokes
        // get amount user has for the token
        // get usd value of total user collateral
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralTokenAmount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, collateralTokenAmount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Chainlink Price Feeds for ETH/USD and BTC/USD come with 1e8 precision
        // so we have to multiply to price by 1e10 (ADDITIONAL_FEED_PRECISION) to get the correct 18 decimals (1e18 precision)
        // Because we are then multiplying two numbers of 1e18 precision (price * amount), we would endup with 1e36 precision
        // Therefore we need to divide by 1e18 to get the correct 18 decimals (1e18 precision)
        // Step by step:
        // 1. uint256(price) * ADDITIONAL_FEED_PRECISION = 1e18 precision
        // 2. 1e18 * amount = 1e36 precision
        // 3. 1e36 / 1e18 = 1e18 precision
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address collateralTokenAddress, uint256 usdAmountInWei)
        public
        view
        returns (uint256 tokenAmountFromUsd)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[collateralTokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Because USD does not have 18 decimals, we need to multiply by PRECISION
        // Because price comes with 1e8 precision, we need to multiply by ADDITIONAL_FEED_PRECISION
        tokenAmountFromUsd = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
}
