// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./ERC20/IERC20.sol";
import "./ERC20/IERC20Permit.sol";
import "./ERC20/IBERC20.sol";
import "./ERC20/SafeERC20.sol";
import "./interfaces/IERC3156FlashBorrower.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "./interfaces/IBTokenProxy.sol";
import "./interfaces/IBumperCore.sol";
import "./interfaces/IOracle.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";

/**
 * @title BumperCore contract
 * @author crypto-pumpkin
 * Bumper Pair: collateral, paired token, expiry, mintRatio
 *  - ! Paired Token cannot be a deflationary token !
 *  - bTokens have same decimals of each paired token
 *  - all Ratios are 1e18
 *  - bTokens have same decimals as Paired Token
 *  - Collateral can be deflationary token, but not rebasing token
 */
contract BumperCore is Initializable, Ownable, ReentrancyGuard, IBumperCore, IERC3156FlashLender {
  using SafeERC20 for IERC20;

  // following ERC3156 https://eips.ethereum.org/EIPS/eip-3156
  bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  bool public override paused;
  IOracle public override oracle;
  // like admin who can pause the project
  address public override responder;
  address public override feeReceiver;
  address public override bERC20Impl;
  uint256 public override flashLoanRate;

  address[] public override collaterals;
  /// @notice collateral => minimum collateralization ratio, paired token default to 1e18
  /// unit 100% <==> 1e18
  mapping(address => uint256) public override minColRatioMap;
  /// @notice collateral => pairedToken => expiry => mintRatio => Pair
  mapping(address => mapping(address => mapping(uint48 => mapping(uint256 => Pair)))) public override pairs;
  mapping(address => Pair[]) private pairList;
  mapping(address => uint256) public override feesMap;

  modifier onlyNotPaused() {
    require(!paused, "Bumper: paused");
    _;
  }

  function initialize(address _bERC20Impl, address _feeReceiver) external initializer {
    require(_bERC20Impl != address(0), "Bumper: _bERC20Impl cannot be 0");
    require(_feeReceiver != address(0), "Bumper: _feeReceiver cannot be 0");
    bERC20Impl = _bERC20Impl;
    feeReceiver = _feeReceiver;
    flashLoanRate = 0.00085 ether;
    initializeOwner();
    initializeReentrancyGuard();
  }

  /// @notice market make deposit, deposit paired Token to received bcTokens, considered as an immediately repaid loan
  function mmDeposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    _validateDepositInputs(_col, pair);

    pair.bcToken.mint(msg.sender, _bcTokenAmt);
    feesMap[_paired] = feesMap[_paired] + _bcTokenAmt * pair.feeRate / 1e18;

    // // record loan ammount to colTotal as it is equivalent to be an immediately repaid loan
    // uint256 colAmount = _getColAmtFromBTokenAmt(_bcTokenAmt, _col, address(pair.bcToken), pair.mintRatio);
    // pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal + colAmount;

    // receive paired tokens from sender, deflationary token is not allowed
    IERC20 pairedToken = IERC20(_paired);
    uint256 pairedBalBefore =  pairedToken.balanceOf(address(this));
    pairedToken.safeTransferFrom(msg.sender, address(this), _bcTokenAmt);
    require(pairedToken.balanceOf(address(this)) - pairedBalBefore >= _bcTokenAmt, "Bumper: transfer paired failed");
    emit MarketMakeDeposit(msg.sender, _col, _paired, _expiry, _mintRatio, _bcTokenAmt);
  }

  function mmDepositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt,
    Permit calldata _pairedPermit
  ) external override {
    _permit(_paired, _pairedPermit);
    mmDeposit(_col, _paired, _expiry, _mintRatio, _bcTokenAmt);
  }

  /// @notice deposit collateral to a Bumper Pair, sender receives bcTokens and brTokens
  function deposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    _validateDepositInputs(_col, pair);

    // receive collateral
    IERC20 collateral = IERC20(_col);
    uint256 colBalBefore =  collateral.balanceOf(address(this));
    collateral.safeTransferFrom(msg.sender, address(this), _colAmt);
    uint256 received = collateral.balanceOf(address(this)) - colBalBefore;
    require(received > 0, "Bumper: transfer failed");
    pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal + received;

    // mint bTokens for reveiced collateral
    uint256 mintAmount = _getBTokenAmtFromColAmt(received, _col, _paired, pair.mintRatio);
    pair.bcToken.mint(msg.sender, mintAmount);
    pair.brToken.mint(msg.sender, mintAmount);
    emit Deposit(msg.sender, _col, _paired, _expiry, _mintRatio, received);
  }

  function depositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt,
    Permit calldata _colPermit
  ) external override {
    _permit(_col, _colPermit);
    deposit(_col, _paired, _expiry, _mintRatio, _colAmt);
  }

  /// @notice redeem with brTokens and bcTokens before expiry only, sender receives collateral, fees charged on collateral
  function redeem(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bTokenAmt
  ) external override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Bumper: pair does not exist");
    require(block.timestamp <= pair.expiry, "Bumper: expired, col forfeited");
    pair.brToken.burnByBumper(msg.sender, _bTokenAmt);
    pair.bcToken.burnByBumper(msg.sender, _bTokenAmt);

    // send collateral to sender
    uint256 colAmountToPay = _getColAmtFromBTokenAmt(_bTokenAmt, _col, address(pair.bcToken), pair.mintRatio);
    // once redeemed, it won't be considered as a loan for the pair anymore
    pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal - colAmountToPay;
    // accrue fees on payment
    _sendAndAccuFees(IERC20(_col), colAmountToPay, pair.feeRate, true /* accrue */);
    emit Redeem(msg.sender, _col, _paired, _expiry, _mintRatio, _bTokenAmt);
  }

  /// @notice repay with brTokens and paired token amount, sender receives collateral, no fees charged on collateral
  function repay(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _brTokenAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Bumper: pair does not exist");
    require(block.timestamp <= pair.expiry, "Bumper: expired, col forfeited");
    pair.brToken.burnByBumper(msg.sender, _brTokenAmt);

    // receive paired tokens from sender, deflationary token is not allowed
    IERC20 pairedToken = IERC20(_paired);
    uint256 pairedBalBefore =  pairedToken.balanceOf(address(this));
    pairedToken.safeTransferFrom(msg.sender, address(this), _brTokenAmt);
    require(pairedToken.balanceOf(address(this)) - pairedBalBefore >= _brTokenAmt, "Bumper: transfer paired failed");
    feesMap[_paired] = feesMap[_paired] + _brTokenAmt * pair.feeRate / 1e18;

    // send collateral back to sender
    uint256 colAmountToPay = _getColAmtFromBTokenAmt(_brTokenAmt, _col, address(pair.brToken), pair.mintRatio);
    _safeTransfer(IERC20(_col), msg.sender, colAmountToPay);
    emit Repay(msg.sender, _col, _paired, _expiry, _mintRatio, _brTokenAmt);
  }

  function repayWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _brTokenAmt,
    Permit calldata _pairedPermit
  ) external override {
    _permit(_paired, _pairedPermit);
    repay(_col, _paired, _expiry, _mintRatio, _brTokenAmt);
  }

  /// @notice sender collect paired tokens by returning same amount of bcTokens to Bumper
  function collect(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) external override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Bumper: pair does not exist");
    require(block.timestamp > pair.expiry, "Bumper: not ready");
    pair.bcToken.burnByBumper(msg.sender, _bcTokenAmt);

    IERC20 pairedToken = IERC20(_paired);
    uint256 brTokenAmtDefaulted = pair.brToken.totalSupply();
    if (brTokenAmtDefaulted == 0) { // no default, send paired Token to sender
      // no fees accrued as it is accrued on Borrower payment
      _sendAndAccuFees(pairedToken, _bcTokenAmt, pair.feeRate, false /* accrue */);
    } else {
      // total amount of brTokens ever minted (converted from total collateral received, redeemed collateral not counted)
      uint256 brTokenEverMinted = _getBTokenAmtFromColAmt(pair.colTotal, _col, _paired, pair.mintRatio);
      // paired token amount to pay = bcToken amount * (1 - default ratio)
      uint256 pairedTokenAmtToCollect = _bcTokenAmt * (brTokenEverMinted - brTokenAmtDefaulted) / brTokenEverMinted;
      // no fees accrued as it is accrued on Borrower payment
      _sendAndAccuFees(pairedToken, pairedTokenAmtToCollect, pair.feeRate, false /* accrue */);

      // default collateral amount to pay = converted collateral amount (from bcTokenAmt) * default ratio
      uint256 colAmount = _getColAmtFromBTokenAmt(_bcTokenAmt, _col, address(pair.bcToken), pair.mintRatio);
      uint256 colAmountToCollect = colAmount * brTokenAmtDefaulted / brTokenEverMinted;
      // accrue fees on defaulted collateral since it was never accrued
      _sendAndAccuFees(IERC20(_col), colAmountToCollect, pair.feeRate, true /* accrue */);
    }
    emit Collect(msg.sender, _col, _paired,_expiry,  _mintRatio, _bcTokenAmt);
  }

  /// @notice anyone can call if they pay, no reason to prevent that. This will enable future xBumper or other fee related features
  function collectFees(IERC20[] calldata _tokens) external override {
    for (uint256 i = 0; i < _tokens.length; i++) {
      IERC20 token = _tokens[i];
      uint256 fee = feesMap[address(token)];
      feesMap[address(token)] = 0;
      _safeTransfer(token, feeReceiver, fee);
    }
  }

  /**
   * @notice add a new Bumper Pair
   *  - Paired Token cannot be a deflationary token
   *  - minColRatio is not respected if collateral is alreay added
   *  - all Ratios are 1e18
   */
  function addPair(
    address _col,
    address _paired,
    uint48 _expiry,
    string calldata _expiryStr,
    uint256 _mintRatio,
    string calldata _mintRatioStr,
    uint256 _feeRate
  ) external override onlyOwner {
    require(pairs[_col][_paired][_expiry][_mintRatio].mintRatio == 0, "Bumper: pair exists");
    require(_mintRatio > 0, "Bumper: _mintRatio <= 0");
    require(_feeRate < 0.1 ether, "Bumper: fee rate must be < 10%");
    require(_expiry > block.timestamp, "Bumper: expiry in the past");
    require(minColRatioMap[_col] > 0, "Bumper: col not listed");
    minColRatioMap[_paired] = 1e18; // default paired token to 100% collateralization ratio as most of them are stablecoins, can be updated later.

    Pair memory pair = Pair({
      active: true,
      feeRate: _feeRate,
      mintRatio: _mintRatio,
      expiry: _expiry,
      pairedToken: _paired,
      bcToken: IBERC20(_createBToken(_col, _paired, _expiry, _expiryStr, _mintRatioStr, "BC_")),
      brToken: IBERC20(_createBToken(_col, _paired, _expiry, _expiryStr, _mintRatioStr, "BR_")),
      colTotal: 0
    });
    pairs[_col][_paired][_expiry][_mintRatio] = pair;
    pairList[_col].push(pair);
    emit PairAdded(_col, _paired, _expiry, _mintRatio);
  }

  /**
   * @notice allow flash loan borrow allowed tokens up to all core contracts' holdings
   * _receiver will received the requested amount, and need to payback the loan amount + fees
   * _receiver must implement IERC3156FlashBorrower
   */
  function flashLoan(
    IERC3156FlashBorrower _receiver,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) public override onlyNotPaused nonReentrant returns (bool) {
    require(minColRatioMap[_token] > 0, "Bumper: token not allowed");
    IERC20 token = IERC20(_token);
    uint256 tokenBalBefore = token.balanceOf(address(this));
    token.safeTransfer(address(_receiver), _amount);
    uint256 fees = flashFee(_token, _amount);
    require(
      _receiver.onFlashLoan(msg.sender, _token, _amount, fees, _data) == FLASHLOAN_CALLBACK_SUCCESS,
      "IERC3156: Callback failed"
    );
    // receive loans and fees
    // token.safeTransferFrom(address(_receiver), address(this), _amount + fees);
    uint256 receivedFees = token.balanceOf(address(this)) - tokenBalBefore;
    require(receivedFees >= fees, "Bumper: not enough fees");
    feesMap[_token] = feesMap[_token] + receivedFees;
    return true;
  }

  /// @notice flashloan rate can be anything
  function setFlashLoanRate(uint256 _newRate) external override onlyOwner {
    emit FlashLoanRateUpdated(flashLoanRate, _newRate);
    flashLoanRate = _newRate;
  }

  /// @notice add new or update existing collateral
  function updateCollateral(address _col, uint256 _minColRatio) external override onlyOwner {
    require(_minColRatio > 0.5 ether, "Bumper: min colRatio < 50%");
    emit CollateralUpdated(_col, minColRatioMap[_col], _minColRatio);
    if (minColRatioMap[_col] == 0) {
      collaterals.push(_col);
    }
    minColRatioMap[_col] = _minColRatio;
  }

  function setPairActive(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    bool _active
  ) external override onlyOwner {
    pairs[_col][_paired][_expiry][_mintRatio].active = _active;
  }

  function setFeeReceiver(address _address) external override onlyOwner {
    require(_address != address(0), "Bumper: address cannot be 0");
    emit AddressUpdated('feeReceiver', feeReceiver, _address);
    feeReceiver = _address;
  }

  /// @dev update this will only affect pools deployed after
  function setBERC20Impl(address _newImpl) external override onlyOwner {
    require(_newImpl != address(0), "Bumper: _newImpl cannot be 0");
    emit BERC20ImplUpdated(bERC20Impl, _newImpl);
    bERC20Impl = _newImpl;
  }

  function setPaused(bool _paused) external override {
    require(msg.sender == owner() || msg.sender == responder, "Bumper: not owner/responder");
    emit PausedStatusUpdated(paused, _paused);
    paused = _paused;
  }

  function setResponder(address _address) external override onlyOwner {
    require(_address != address(0), "Bumper: address cannot be 0");
    emit AddressUpdated('responder', responder, _address);
    responder = _address;
  }

  function setOracle(address _address) external override onlyOwner {
    require(_address != address(0), "Bumper: address cannot be 0");
    emit AddressUpdated('oracle', address(oracle), _address);
    oracle = IOracle(_address);
  }

  function getCollaterals() external view override returns (address[] memory) {
    return collaterals;
  }

  function getPairList(address _col) external view override returns (Pair[] memory) {
    Pair[] memory colPairList = pairList[_col];
    Pair[] memory _pairs = new Pair[](colPairList.length);
    for (uint256 i = 0; i < colPairList.length; i++) {
      Pair memory pair = colPairList[i];
      _pairs[i] = pairs[_col][pair.pairedToken][pair.expiry][pair.mintRatio];
    }
    return _pairs;
  }

  /// @notice amount that is eligible to collect
  function viewCollectible(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _bcTokenAmt
  ) external view override returns (uint256 colAmtToCollect, uint256 pairedAmtToCollect) {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    if (pair.mintRatio == 0 || block.timestamp < pair.expiry) return (colAmtToCollect, pairedAmtToCollect);

    uint256 brTokenAmtDefaulted = pair.brToken.totalSupply();
    if (brTokenAmtDefaulted == 0) { // no default, transfer paired Token
      pairedAmtToCollect =  _bcTokenAmt;
    } else {
      // total amount of brTokens ever minted (converted from total collateral received, redeemed collateral not counted)
      uint256 brTokenEverMinted = _getBTokenAmtFromColAmt(pair.colTotal, _col, _paired, pair.mintRatio);
      // paired token amount to pay = bcToken amount * (1 - default ratio)
      pairedAmtToCollect = _bcTokenAmt * (brTokenEverMinted - brTokenAmtDefaulted) * (1e18 - pair.feeRate) / 1e18 / brTokenEverMinted;

      // default collateral amount to pay = converted collateral amount (from bcTokenAmt) * default ratio
      uint256 colAmount = _getColAmtFromBTokenAmt(_bcTokenAmt, _col, address(pair.bcToken), pair.mintRatio);
      colAmtToCollect = colAmount * brTokenAmtDefaulted / brTokenEverMinted;
    }
  }

  function maxFlashLoan(address _token) external view override returns (uint256) {
    return IERC20(_token).balanceOf(address(this));
  }

  /// @notice returns the amount of fees charges by for the loan amount. 0 means no fees charged, may not have the token
  function flashFee(address _token, uint256 _amount) public view override returns (uint256 _fees) {
    if (minColRatioMap[_token] > 0) {
      _fees = _amount * flashLoanRate / 1e18;
    }
  }

  /// @notice version of current Bumper Core hardcoded
  function version() external pure override returns (string memory) {
    return '1.0';
  }

  function _safeTransfer(IERC20 _token, address _account, uint256 _amount) private {
    uint256 bal = _token.balanceOf(address(this));
    if (bal < _amount) {
      _token.safeTransfer(_account, bal);
    } else {
      _token.safeTransfer(_account, _amount);
    }
  }

  function _sendAndAccuFees(IERC20 _token, uint256 _amount, uint256 _feeRate, bool _accrue) private {
    uint256 fees = _amount * _feeRate / 1e18;
    _safeTransfer(_token, msg.sender, _amount - fees);
    if (_accrue) {
      feesMap[address(_token)] = feesMap[address(_token)] + fees;
    }
  }

  function _createBToken(
    address _col,
    address _paired,
    uint256 _expiry,
    string calldata _expiryStr,
    string calldata _mintRatioStr,
    string memory _prefix
  ) private returns (address proxyAddr) {
    uint8 decimals = uint8(IERC20(_paired).decimals());
    if (decimals == 0) {
      decimals = 18;
    }
    string memory symbol = string(abi.encodePacked(
      _prefix,
      IERC20(_col).symbol(), "_",
      _mintRatioStr, "_",
      IERC20(_paired).symbol(), "_",
      _expiryStr
    ));

    bytes32 salt = keccak256(abi.encodePacked(_col, _paired, _expiry, _mintRatioStr, _prefix));
    proxyAddr = Clones.cloneDeterministic(bERC20Impl, salt);
    IBTokenProxy(proxyAddr).initialize("Bumper Protocol bToken", symbol, decimals);
    emit BTokenCreated(proxyAddr);
  }

  function _getBTokenAmtFromColAmt(uint256 _colAmt, address _col, address _paired, uint256 _mintRatio) private view returns (uint256) {
    uint8 colDecimals = IERC20(_col).decimals();
    // pairedDecimals is the same as bToken decimals
    uint8 pairedDecimals = IERC20(_paired).decimals();
    return _colAmt * _mintRatio * (10 ** pairedDecimals) / (10 ** colDecimals) / 1e18;
  }

  function _getColAmtFromBTokenAmt(uint256 _bTokenAmt, address _col, address _bToken, uint256 _mintRatio) private view returns (uint256) {
    uint8 colDecimals = IERC20(_col).decimals();
    // pairedDecimals == bToken decimals
    uint8 bTokenDecimals = IERC20(_bToken).decimals();
    return _bTokenAmt * (10 ** colDecimals) * 1e18 / _mintRatio / (10 ** bTokenDecimals);
  }

  function _permit(address _token, Permit calldata permit) private {
    IERC20Permit(_token).permit(
      permit.owner,
      permit.spender,
      permit.amount,
      permit.deadline,
      permit.v,
      permit.r,
      permit.s
    );
  }

  function _validateDepositInputs(address _col, Pair memory _pair) private view {
    require(_pair.mintRatio != 0, "Bumper: pair does not exist");
    require(_pair.active, "Bumper: pair inactive");
    require(_pair.expiry > block.timestamp, "Bumper: pair expired");

    // Oracle price is not required, the consequence is low since it will just allow users to deposit collateral (which can be collected thro repay before expiry. If default, early repayments will be diluted
    if (address(oracle) != address(0)) {
      uint256 colPrice = oracle.getPriceUSD(_col);
      if (colPrice != 0) {
        // pairedPrice set to be 1e18
        uint256 pairedPrice = 1e18;
        // colPrice / mintRatio (1e18) / pairedPrice > min collateralization ratio (1e18), if yes, revert deposit
        require(colPrice * 1e36 > minColRatioMap[_col] * _pair.mintRatio * pairedPrice, "Bumper: collateral price too low");
      }
    }
  }
}