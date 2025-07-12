// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author otomdee
 * @notice This contract handles the logic for minting and redeeming DSC,
 * depositing and withdrawing collateral
 */

contract DSCEngine is ReentrancyGuard {
    //////////////
    /// Errors ///
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();

    ///////////////////////
    /// State Variables ///
    ///////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized, 50 here represents 0.5 when combined with the precision
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_amountDscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////
    /// Events ///
    //////////////

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amountDeposited);

    //////////////
    // Modifiers//
    //////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    /// External Functions ///
    //////////////////////////
    function depositCollateralAndMintDsc() external {}

    /*
     *@param tokenCollateralAddress Address of collateral token being deposited
     *@param amount Amount of token being deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        external
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemDscForCollateral() external {}

    function redeemCollateral() external {}

    /*
     *@param amountDsc Amount of dsc to be minted
     *@notice caller must have more collateral value than the minimum threshold
    */
    function mint(uint256 amountDsc) external moreThanZero(amountDsc) nonReentrant {
        s_amountDscMinted[msg.sender] += amountDsc;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDsc);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burn() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ///////////////////////////////////////////
    /// Private and Internal view Functions ///
    ///////////////////////////////////////////

    /**
     * Returns how close to liquidation a user is
     * If health factor is below 1, user can get liquidated
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCminted, uint256 collateralValueInUsd)
    {
        totalDSCminted = s_amountDscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);

        return (totalDSCminted, collateralValueInUsd);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCminted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        //HF = collateralValueUsd/totalDSCminted, then solidity decimal precision and collateral threshold accounted for
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION / totalDSCminted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////////
    /// Public and External view Functions ////
    ///////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256) {
        //loop through all collateral tokens,
        //get each of their current USD prices,
        //calculate user's total USD collateral value
        uint256 value = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            //get price
            value += getUsdValue(token, amount);
        }

        return value;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //price is returned as 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
