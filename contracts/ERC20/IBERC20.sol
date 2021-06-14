// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import './IERC20.sol';

/**
 * @title BERC20 contract interface, implements {IERC20}. See {BERC20}.
 * @author crypto-pumpkin
 */
interface IBERC20 is IERC20 {
    /// @notice access restriction - owner (R)
    function mint(address _account, uint256 _amount) external returns (bool);
    function burnByBumper(address _account, uint256 _amount) external returns (bool);
}