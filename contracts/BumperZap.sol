// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20/IERC20.sol";
import "./ERC20/IERC20Permit.sol";
import "./ERC20/SafeERC20.sol";
import "./ERC20/IBERC20.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IBumperCore.sol";
import "./interfaces/IBumperZap.sol";
import "./utils/Ownable.sol";

/**
 * @title Bumper Protocol Zap
 * @author alan
 * Main logic is in _depositAndAddLiquidity & _depositAndSwapToPaired
 */
contract BumperZap is Ownable, IBumperZap {
    using SafeERC20 for IERC20;
    IBumperCore public override core;
    IRouter public override router;

    constructor (IBumperCore _core, IRouter _router) {
        require(address(_core) != address(0), "BumperZap: _core is 0");
        require(address(_router) != address(0), "BumperZap: _router is 0");
        core = _core;
        router = _router;
        initializeOwner();
    }

    /**
    * @notice Deposit collateral `_col` to receive paired token `_paired` and brTokens
    *  - deposits collateral to receive bcTokens and brTokens
    *  - bcTokens are swapped into paired token through router
    *  - paired token and brTokens are sent to sender
    */
    function depositAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline
    ) external override {
        _depositAndSwapToPaired(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _minPairedOut, 
            _path, 
            _deadline
        );
    }

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
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _depositAndSwapToPaired(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _minPairedOut, 
            _path, 
            _deadline
        );
    }

    /**
    * @notice Deposit collateral `_col` to receive LP tokens and brTokens
    *  - deposits collateral to receive bcTokens and brTokens
    *  - transfers paired token from sender
    *  - bcTokens and `_paired` tokens are added as liquidity to receive LP tokens
    *  - LP tokens and brTokens are sent to sender
    */
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
    ) external override {
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

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
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

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
    ) external override {
        _permit(IERC20Permit(_paired), _pairedPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

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
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _permit(IERC20Permit(_paired), _pairedPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

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
    ) external override {
        _mmDepositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

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
    ) external override {
        _permit(IERC20Permit(_paired), _pairedPermit);
        _mmDepositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _bcTokenDepositAmt, 
            _pairedDepositAmt, 
            _bcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    /// @notice This contract should never hold any funds.
    /// Any tokens sent here by accident can be retreived.
    function collect(IERC20 _token) external override onlyOwner {
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, "BumperZap: balance is 0");
        _token.safeTransfer(msg.sender, balance);
    }

    function updateCore(IBumperCore _core) external override onlyOwner {
        require(address(_core) != address(0), "BumperZap: _core is 0");
        core = _core;
    }

    function updateRouter(IRouter _router) external override onlyOwner {
        require(address(_router) != address(0), "BumperZap: _router is 0");
        router = _router;
    }

    /// @notice check received amount from swap, tokenOut is always the last in array
    function getAmountOut(
        uint256 _tokenInAmt, 
        address[] calldata _path
    ) external view override returns (uint256) {
        return router.getAmountsOut(_tokenInAmt, _path)[_path.length - 1];
    }

    function _depositAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline
    ) private {
        require(_colAmt > 0, "BumperZap: _colAmt is 0");
        require(_path.length >= 2, "BumperZap: _path length < 2");
        require(_path[_path.length - 1] == _paired, "BumperZap: output != _paired");
        require(_deadline >= block.timestamp, "BumperZap: _deadline in past");
        (address _bcToken, uint256 _bcTokensReceived, ) = _deposit(_col, _paired, _expiry, _mintRatio, _colAmt);

        require(_path[0] == _bcToken, "BumperZap: input != bcToken");
        _approve(IERC20(_bcToken), address(router), _bcTokensReceived);
        router.swapExactTokensForTokens(_bcTokensReceived, _minPairedOut, _path, msg.sender, _deadline);
    }

    function _depositAndAddLiquidity(
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
    ) private {
        require(_colAmt > 0, "BumperZap: _colAmt is 0");
        require(_deadline >= block.timestamp, "BumperZap: _deadline in past");
        require(_bcTokenDepositAmt > 0, "BumperZap: 0 bcTokenDepositAmt");
        require(_bcTokenDepositAmt >= _bcTokenDepositMin, "BumperZap: bcToken Amt < min");
        require(_pairedDepositAmt > 0, "BumperZap: 0 pairedDepositAmt");
        require(_pairedDepositAmt >= _pairedDepositMin, "BumperZap: paired Amt < min");

        // deposit collateral to Bumper
        IERC20 bcToken;
        uint256 bcTokenBalBefore;
        { // scope to avoid stack too deep errors
            (address _bcToken, uint256 _bcTokensReceived, uint256 _bcTokenBalBefore) = _deposit(_col, _paired, _expiry, _mintRatio, _colAmt);
            require(_bcTokenDepositAmt <= _bcTokensReceived, "BumperZap: bcToken Amt > minted");
            bcToken = IERC20(_bcToken);
            bcTokenBalBefore = _bcTokenBalBefore;
        }

        // received paired tokens from sender
        IERC20 paired = IERC20(_paired);
        uint256 pairedBalBefore = paired.balanceOf(address(this));
        paired.safeTransferFrom(msg.sender, address(this), _pairedDepositAmt);
        uint256 receivedPaired = paired.balanceOf(address(this)) - pairedBalBefore;
        require(receivedPaired > 0, "BumperZap: paired transfer failed");

        // add liquidity for sender
        _approve(bcToken, address(router), _bcTokenDepositAmt);
        _approve(paired, address(router), _pairedDepositAmt);
        router.addLiquidity(
            address(bcToken), 
            address(paired), 
            _bcTokenDepositAmt, 
            receivedPaired, 
            _bcTokenDepositMin,
            _pairedDepositMin,
            msg.sender,
            _deadline
        );

        // sending leftover tokens back to sender
        _transferRem(bcToken, bcTokenBalBefore);
        _transferRem(paired, pairedBalBefore);
    }

    function _mmDepositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _bcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _bcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) private {
        require(_deadline >= block.timestamp, "BumperZap: _deadline in past");
        require(_bcTokenDepositAmt > 0, "BumperZap: 0 bcTokenDepositAmt");
        require(_bcTokenDepositAmt >= _bcTokenDepositMin, "BumperZap: bcToken Amt < min");
        require(_pairedDepositAmt > 0, "BumperZap: 0 pairedDepositAmt");
        require(_pairedDepositAmt >= _pairedDepositMin, "BumperZap: paired Amt < min");

        // transfer all paired tokens from sender to this contract
        IERC20 paired = IERC20(_paired);
        uint256 pairedBalBefore = paired.balanceOf(address(this));
        paired.safeTransferFrom(msg.sender, address(this), _bcTokenDepositAmt + _pairedDepositAmt);
        require(paired.balanceOf(address(this)) - pairedBalBefore == _bcTokenDepositAmt + _pairedDepositAmt, "BumperZap: paired transfer failed");

        // mmDeposit paired to Bumper to receive bcTokens
        ( , , , IBERC20 bcToken, , , , ) = core.pairs(_col, _paired, _expiry, _mintRatio);
        require(address(bcToken) != address(0), "BumperZap: pair not exist");
        uint256 bcTokenBalBefore = bcToken.balanceOf(address(this));
        _approve(paired, address(core), _bcTokenDepositAmt);
        core.mmDeposit(_col, _paired, _expiry, _mintRatio, _bcTokenDepositAmt);
        uint256 bcTokenReceived = bcToken.balanceOf(address(this)) - bcTokenBalBefore;
        require(_bcTokenDepositAmt <= bcTokenReceived, "BumperZap: bcToken Amt > minted");

        // add liquidity for sender
        _approve(bcToken, address(router), bcTokenReceived);
        _approve(paired, address(router), _pairedDepositAmt);
        router.addLiquidity(
            address(bcToken),
            _paired,
            bcTokenReceived, 
            _pairedDepositAmt, 
            _bcTokenDepositMin,
            _pairedDepositMin,
            msg.sender,
            _deadline
        );

        // sending leftover tokens (since the beginning of user call) back to sender
        _transferRem(bcToken, bcTokenBalBefore);
        _transferRem(paired, pairedBalBefore);
    }

    function _deposit(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt
    ) private returns (address bcTokenAddr, uint256 bcTokenReceived, uint256 bcTokenBalBefore) {
        ( , , , IBERC20 bcToken, IBERC20 brToken, , , ) = core.pairs(_col, _paired, _expiry, _mintRatio);
        require(address(bcToken) != address(0) && address(brToken) != address(0), "BumperZap: pair not exist");
        // receive collateral from sender
        IERC20 collateral = IERC20(_col);
        uint256 colBalBefore = collateral.balanceOf(address(this));
        collateral.safeTransferFrom(msg.sender, address(this), _colAmt);
        uint256 received = collateral.balanceOf(address(this)) - colBalBefore;
        require(received > 0, "BumperZap: col transfer failed");

        // deposit collateral to Bumper
        bcTokenBalBefore = bcToken.balanceOf(address(this));
        uint256 brTokenBalBefore = brToken.balanceOf(address(this));
        _approve(collateral, address(core), received);
        core.deposit(_col, _paired, _expiry, _mintRatio, received);

        // send brToken back to sender, and record received bcTokens
        _transferRem(brToken, brTokenBalBefore);
        bcTokenReceived = bcToken.balanceOf(address(this)) - bcTokenBalBefore;
        bcTokenAddr = address(bcToken);
    }

    function _approve(IERC20 _token, address _spender, uint256 _amount) private {
        uint256 allowance = _token.allowance(address(this), _spender);
        if (allowance < _amount) {
            if (allowance != 0) {
                _token.safeApprove(_spender, 0);
            }
            _token.safeApprove(_spender, type(uint256).max);
        }
    }

    function _permit(IERC20Permit _token, Permit calldata permit) private {
        _token.permit(
            permit.owner,
            permit.spender,
            permit.amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
    }

    // transfer remaining amount (since the beginnning of action) back to sender
    function _transferRem(IERC20 _token, uint256 _balBefore) private {
        uint256 tokensLeftover = _token.balanceOf(address(this)) - _balBefore;
        if (tokensLeftover > 0) {
            _token.safeTransfer(msg.sender, tokensLeftover);
        }
    }
}