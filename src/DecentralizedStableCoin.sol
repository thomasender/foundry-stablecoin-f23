// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralised Stable Coin
 * @author Thomas Ender
 * Collateral: wEth, wBtc
 * Minting: Algorithmic
 * Relative Stability: 1 DSC = 1 USD
 *
 * Meant to be governed by DSCEngine.sol.
 * The ERC20 Contract of this Decentralised Stable Coin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable() {}

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        /// super uses burn function of ERC20Burnable
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool success) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        success = true;
    }
}
