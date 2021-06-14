// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./ERC20/ERC20Permit.sol";
import "./utils/Ownable.sol";

/**
 * @title Bumper Protocol Governance Token
 * @author crypto-pumpkin
 */
contract BUMPER is ERC20Permit, Initializable, Ownable {
  uint256 public constant CAP = 1000000 ether;

  function initialize() external initializer {
    initializeOwner();
    initializeERC20("Bumper Protocol", "BUMPER", 18);
    initializeERC20Permit("Bumper Protocol");
    _mint(msg.sender, CAP);
  }

  // collect any tokens sent by mistake
  function collect(address _token) external {
    if (_token == address(0)) { // token address(0) = ETH
      Address.sendValue(payable(owner()), address(this).balance);
    } else {
      uint256 balance = IERC20(_token).balanceOf(address(this));
      IERC20(_token).transfer(owner(), balance);
    }
  }
}