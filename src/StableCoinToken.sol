// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

/// @title A Decentralized Stable Coin
/// @author Gabriel Lira (github: gabriel-liraa)
/// @dev An algorithmic, exogenous stable coin, pegged to USD,
/// taking wBTC and wETH as collaterals.
/// This is just the ERC20 implementation, meant to be governed by
/// SCTEngine.sol contract.

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StableCoinToken is ERC20Burnable, Ownable {
    error StableCoinToken__AmountToBurnIsLessThanBalance();
    error StableCoinToken__AddressCantBeZero();
    error StableCoinToken__AmountMustBeMoreThanZero();

    constructor() ERC20("StableCoinToken", "SCT") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableCoinToken__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableCoinToken__AmountToBurnIsLessThanBalance();
        }

        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableCoinToken__AddressCantBeZero();
        }

        if (_amount <= 0) {
            revert StableCoinToken__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
