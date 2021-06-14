// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOracleLink {
    function update() external;
    function getPrice(address token) external view returns (uint256 priceAverage, uint32 timeElapsed);
}