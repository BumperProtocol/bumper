// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import '../ERC20/IERC20.sol';
import './IBumperCore.sol';
import './IRouter.sol';

interface IBumperZap {

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
    function core() external view returns (IBumperCore);
    function router() external view returns (IRouter);

    // extra view
    function getAmountOut(uint256 _tokenInAmt, address[] calldata _path) external view returns (uint256);

    // user interactions
    function depositAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline
    ) external;

    function depositWithPermitAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline,
        Permit calldata _colPermit
    ) external;

    function depositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) external;

    function depositWithColPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _colPermit
    ) external;

    function depositWithPairedPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _pairedPermit
    ) external;

    function depositWithBothPermitsAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _colPermit,
        Permit calldata _pairedPermit
    ) external;

    function mmDepositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) external;

    function mmDepositWithPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _pairedPermit
    ) external;

    // admin
    function collect(IERC20 _token) external;
    function updateCore(IBumperCore _core) external;
    function updateRouter(IRouter _router) external;
}