// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

import {StableCoinToken} from "src/StableCoinToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Stable Coin Token Engine
/// @author Gabriel Lira (github: gabriel-liraa)
/// @notice This is the main contract of this projects,
/// it controlls all the logic behind, minting, burning STC and
/// depositing and withdrawing collaterals (wETH and wBTC).
/// @dev An algorithmic, exogenous stable coin, pegged to USD,
/// taking wBTC and wETH as collaterals.
contract SCTEngine is ReentrancyGuard {
    // Errors
    error SCTEngine__AmountLessOrEqualToZero();
    error SCTEngine__EachTokenMustHaveAPriceFeed();
    error SCTEngine__TokenAddressIsNotAllowed();
    error SCTEngine__TransferFailed();
    error SCTEngine__HealthFactorBelowMinimum();
    error SCTEngine__MintingFailed();
    error SCTEngine__RedeemFailed();
    error SCTEngine__UserCanNotBeLiquidated();

    // State Variables
    uint256 private constant PRICE_FEED_PRECISION_FIX = 1e10;
    uint256 private constant HEALTH_FACTOR_THRESHOLD = 50;
    uint256 private constant HEALTH_FACTOR_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;

    StableCoinToken immutable i_sct;

    address[] s_tokenAddresses;

    mapping(address token => address priceFeed) private s_tokenToPriceFeed;
    mapping(address user => mapping(address tokenAddress => uint256 amount))
        private s_userToCollateralDeposited;
    mapping(address user => uint256 sct) private s_userToTokenAmount;

    // Events
    event CollateralDeposited(
        address indexed userAddress,
        address indexed collateralTokenAddress,
        uint256 indexed collateralAmount
    );

    event CollateralRedeemed(
        address indexed fromAddress,
        address indexed toAddress,
        address indexed collateralTokenAddress,
        uint256 collateralAmount
    );

    // Modifiers
    modifier amountGreaterThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert SCTEngine__AmountLessOrEqualToZero();
        }
        _;
    }

    // POSSO COLOCAR QUALQUER TOKEN
    modifier isTokenAllowed(address _tokenAddress) {
        if (_tokenAddress == address(0)) {
            revert SCTEngine__TokenAddressIsNotAllowed();
        }
        _;
    }

    // Constructor
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address sctAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert SCTEngine__EachTokenMustHaveAPriceFeed();
        }

        for (uint256 size = 0; size < tokenAddresses.length; size++) {
            s_tokenToPriceFeed[tokenAddresses[size]] = priceFeedAddresses[size];
        }

        s_tokenAddresses = tokenAddresses;

        i_sct = StableCoinToken(sctAddress);
    }

    // Public & External Functions

    function depositCollateralAndMintSct(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        uint256 _amountToMint
    ) external {
        depositCollateral(_collateralTokenAddress, _collateralAmount);
        mintSct(_amountToMint);
    }

    function depositCollateral(
        address _collateralTokenAddress,
        uint256 _collateralAmount
    )
        public
        nonReentrant
        isTokenAllowed(_collateralTokenAddress)
        amountGreaterThanZero(_collateralAmount)
    {
        s_userToCollateralDeposited[msg.sender][
            _collateralTokenAddress
        ] += _collateralAmount;

        emit CollateralDeposited(
            msg.sender,
            _collateralTokenAddress,
            _collateralAmount
        );

        bool success = IERC20(_collateralTokenAddress).transferFrom(
            msg.sender,
            address(this),
            _collateralAmount
        );

        if (!success) {
            revert SCTEngine__TransferFailed();
        }
    }

    function mintSct(
        uint256 _amount
    ) public nonReentrant amountGreaterThanZero(_amount) {
        s_userToTokenAmount[msg.sender] += _amount;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool success = i_sct.mint(msg.sender, _amount);
        if (!success) {
            revert SCTEngine__MintingFailed();
        }
    }

    function redeemCollateralForSct(
        address _token,
        uint256 _collateralAmount,
        uint256 _sctAmount
    ) external {
        burnSct(_sctAmount);
        redeemCollateral(_token, _collateralAmount);
    }

    function redeemCollateral(
        address _token,
        uint256 _amount
    ) public nonReentrant amountGreaterThanZero(_amount) {
        _redeemCollateral(_token, msg.sender, msg.sender, _amount);
    }

    function burnSct(
        uint256 _amount
    ) public nonReentrant amountGreaterThanZero(_amount) {
        _burnSct(_amount, msg.sender, msg.sender);
    }

    function liquidate(
        address _user,
        address _token,
        uint256 _debtAmountToLiquidate
    ) external nonReentrant amountGreaterThanZero(_debtAmountToLiquidate) {
        if (_healthFactor(_user) > MINIMUM_HEALTH_FACTOR) {
            revert SCTEngine__UserCanNotBeLiquidated();
        }

        uint256 tokenPrice = _getTokenPrice(_token);
        uint256 tokenAmountToLiquidate = (_debtAmountToLiquidate * 1e18) /
            tokenPrice;
        uint256 liquidatorBonus = (tokenAmountToLiquidate * LIQUIDATION_BONUS) /
            LIQUIDATION_PRECISION;

        _redeemCollateral(
            _token,
            _user,
            msg.sender,
            tokenAmountToLiquidate + liquidatorBonus
        );
        _burnSct(tokenAmountToLiquidate, _user, msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    // Private and Internal Functions

    function _burnSct(
        uint256 _amount,
        address _onBehalfOf,
        address _sctFrom
    ) private {
        s_userToTokenAmount[_onBehalfOf] -= _amount;
        bool success = i_sct.transferFrom(_sctFrom, address(this), _amount);
        i_sct.burnFrom(_sctFrom, _amount);
    }

    function _getTokenPrice(
        address _token
    ) private view returns (uint256 priceInUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeed[_token]
        );
        (, int answer, , , ) = priceFeed.latestRoundData();
        priceInUsd = uint256(answer) * PRICE_FEED_PRECISION_FIX;
    }

    function _redeemCollateral(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) private {
        s_userToCollateralDeposited[_from][_token] -= _amount;

        emit CollateralRedeemed(_from, _to, _token, _amount);

        _revertIfHealthFactorIsBroken(msg.sender);

        bool success = IERC20(_token).transfer(_to, _amount);

        if (!success) {
            revert SCTEngine__RedeemFailed();
        }
    }

    function _healthFactor(address user) internal view returns (uint256) {
        uint256 userSctValue = s_userToTokenAmount[user]; // 1e18

        if (userSctValue == 0) return type(uint256).max;

        uint256 userCollateralValue = getAccountCollateralValue(user); // 1e18
        uint256 healthFactorThresholdAdjusted = (userCollateralValue *
            HEALTH_FACTOR_THRESHOLD) / HEALTH_FACTOR_PRECISION;
        return (healthFactorThresholdAdjusted * PRECISION) / userSctValue;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        if (_healthFactor(user) < MINIMUM_HEALTH_FACTOR) {
            revert SCTEngine__HealthFactorBelowMinimum();
        }
    }

    // Private and Internal View Functions

    function getAccountCollateralValue(
        address user
    ) internal view returns (uint256 accountCollateralValue) {
        for (uint256 i = 0; i < s_tokenAddresses.length; i++) {
            address token = s_tokenAddresses[i];
            uint256 tokenAmount = s_userToCollateralDeposited[user][token];
            accountCollateralValue += getCollateralUsdValue(token, tokenAmount);
        }
    }

    function getCollateralUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256 priceInUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeed[token]
        );
        (, int answer, , , ) = priceFeed.latestRoundData();

        priceInUsd =
            ((uint256(answer) * PRICE_FEED_PRECISION_FIX) * amount) /
            1e18;
    }

    function getUserCollateralTokenBalance(
        address token
    ) external view returns (uint256) {
        return s_userToCollateralDeposited[msg.sender][token];
    }

    function getUserSCTBalance() external view returns (uint256) {
        return s_userToTokenAmount[msg.sender];
    }
}
