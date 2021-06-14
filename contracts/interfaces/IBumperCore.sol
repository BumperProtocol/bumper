// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "../ERC20/IBERC20.sol";
import "./IOracle.sol";

/**
 * @title IBumperCore contract interface. See {BumperCore}.
 * @author crypto-pumpkin
 */
interface IBumperCore {
  event BTokenCreated(address);
  event CollateralUpdated(address col, uint256 old, uint256 _new);
  event PairAdded(address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio);
  event MarketMakeDeposit(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Deposit(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Repay(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Redeem(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Collect(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event AddressUpdated(string _type, address old, address _new);
  event PausedStatusUpdated(bool old, bool _new);
  event BERC20ImplUpdated(address bERC20Impl, address newImpl);
  event FlashLoanRateUpdated(uint256 old, uint256 _new);

  // a debit note
  struct Pair {
    bool active;
    uint48 expiry;
    // debit token like dai
    address pairedToken;
    // token used to collect
    IBERC20 bcToken; // Bumper capitol token, e.g. BC_Dai_wBTC_2_2021
    // token used to repay
    IBERC20 brToken; // Bumper repayment token, e.g. BR_Dai_wBTC_2_2021
    // _pair.mintRatio * pairedPrice ~ colPrice
    // 1e18 unit, price of collateral / collateralization ratio
    uint256 mintRatio;
    // 1e18 unit
    uint256 feeRate;
    uint256 colTotal;
  }

  struct Permit {
    address owner;
    address spender;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // state vars
  function oracle() external view returns (IOracle);
  function version() external pure returns (string memory);
  function flashLoanRate() external view returns (uint256);
  function paused() external view returns (bool);
  function responder() external view returns (address);
  function feeReceiver() external view returns (address);
  function bERC20Impl() external view returns (address);
  function collaterals(uint256 _index) external view returns (address);
  function minColRatioMap(address _col) external view returns (uint256);
  function feesMap(address _token) external view returns (uint256);
  function pairs(address _col, address _paired, uint48 _expiry, uint256 _mintRatio) external view returns (
    bool active, 
    uint48 expiry, 
    address pairedToken, 
    IBERC20 bcToken, 
    IBERC20 brToken, 
    uint256 mintRatio, 
    uint256 feeRate, 
    uint256 colTotal
  );

  // extra view
  function getCollaterals() external view returns (address[] memory);
  function getPairList(address _col) external view returns (Pair[] memory);
  function viewCollectible(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) external view returns (uint256 colAmtToCollect, uint256 pairedAmtToCollect);

  // user action - only when not paused
  function mmDeposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) external;
  function mmDepositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt,
    Permit calldata _pairedPermit
  ) external;
  function deposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt
  ) external;
  function depositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt,
    Permit calldata _colPermit
  ) external;
  function redeem(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bTokenAmt
  ) external;
  function repay(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _brTokenAmt
  ) external;
  function repayWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _brTokenAmt,
    Permit calldata _pairedPermit
  ) external;
  function collect(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) external;
  function collectFees(IERC20[] calldata _tokens) external;

  // access restriction - owner (dev) & responder
  function setPaused(bool _paused) external;

  // access restriction - owner (dev)
  function addPair(
    address _col,
    address _paired,
    uint48 _expiry,
    string calldata _expiryStr,
    uint256 _mintRatio,
    string calldata _mintRatioStr,
    uint256 _feeRate
  ) external;
  function setPairActive(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    bool _active
  ) external;
  function updateCollateral(address _col, uint256 _minColRatio) external;
  function setFeeReceiver(address _addr) external;
  function setResponder(address _addr) external;
  function setBERC20Impl(address _addr) external;
  function setOracle(address _addr) external;
  function setFlashLoanRate(uint256 _newRate) external;
}