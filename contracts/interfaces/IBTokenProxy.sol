// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

/**
 * @title Interface of the BTokens Proxy.
 */
interface IBTokenProxy {
  function initialize(string calldata _name, string calldata _symbol, uint8 _decimals) external;
}