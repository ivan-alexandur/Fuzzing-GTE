// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC4626} from "@solady/tokens/ERC4626.sol";
import {EnumerableSetLib} from "@solady/utils/EnumerableSetLib.sol";
import {DynamicArrayLib} from "@solady/utils/DynamicArrayLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

import {IViewPort} from "./interfaces/IViewPort.sol";
import {IOperatorPanel} from "../utils/interfaces/IOperatorPanel.sol";
import {PerpsOperatorRoles} from "../utils/OperatorPanel.sol";

contract GTL is Initializable, ERC4626, OwnableRoles {
    using DynamicArrayLib for uint256[];
    using SafeTransferLib for address;
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;
    using SafeCastLib for *;
    using FixedPointMathLib for *;

    event WithdrawalQueued(uint256 indexed id, address indexed account, uint256 shares);
    event WithdrawalCanceled(uint256 indexed id);
    event WithdrawalProcessed(uint256 indexed id, address indexed account, uint256 shares, uint256 assets);
    event AdminRoleGranted(address indexed account);
    event AdminRoleRevoked(address indexed account);

    error NotPerpManager();
    error InvalidOperator();
    error InsufficientWithdrawalsQueued();
    error NotAdmin();
    error Unused();
    error InsufficientWithdrawal();

    /// @dev The abi version of this impl so the indexer can handle event-changing upgrades
    uint256 public constant ABI_VERSION = 1;

    constructor(address _usdc, address _perpManager) {
        usdc = _usdc;
        perpManager = _perpManager;
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        usdc.safeApprove(perpManager, type(uint256).max);
        _initializeOwner(_owner);
    }

    modifier onlyPerpManager() {
        if (msg.sender != perpManager) revert NotPerpManager();
        _;
    }

    modifier onlyAdmin() {
        _assertAdmin();
        _;
    }

    struct Withdrawal {
        address account;
        uint256 shares;
    }

    address public immutable usdc;
    address public immutable perpManager;

    uint256 public constant ADMIN_ROLE = _ROLE_0;

    EnumerableSetLib.Uint256Set private _subaccounts;

    uint256[] private _withdrawalQueue;

    uint256 private _withdrawalCounter;

    mapping(uint256 id => Withdrawal) internal _queuedWithdrawal;

    mapping(address account => uint256) internal _queuedShares;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                               METADATA
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function name() public pure override returns (string memory) {
        return "GTE Liquidity Pool";
    }

    function symbol() public pure override returns (string memory) {
        return "GTL";
    }

    function asset() public view override returns (address) {
        return usdc;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                  LP
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function queueWithdrawal(uint256 shares) external returns (uint256 id) {
        if (shares == 0) revert InsufficientWithdrawal();
        if (_queuedShares[msg.sender] + shares > balanceOf(msg.sender)) revert InsufficientBalance();

        id = ++_withdrawalCounter;

        _queuedShares[msg.sender] += shares;
        _queuedWithdrawal[id] = Withdrawal(msg.sender, shares);
        _withdrawalQueue.push(id);

        emit WithdrawalQueued(id, msg.sender, shares);
    }

    function cancelWithdrawal(uint256 id) external {
        if (_queuedWithdrawal[id].account != msg.sender) revert NotPerpManager();

        _queuedShares[msg.sender] -= _queuedWithdrawal[id].shares;
        delete _queuedWithdrawal[id];

        _dequeue(id);

        emit WithdrawalCanceled(id);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                ADMIN
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function processWithdrawals(uint256 num) external onlyAdmin {
        if (num > _withdrawalQueue.length) revert InsufficientWithdrawalsQueued();

        uint256 allocatedAssets = orderbookCollateral() + freeCollateralBalance() + totalAccountValue();

        uint256 id;
        Withdrawal memory withdrawal;
        uint256 assets;
        for (uint256 i; i < num; ++i) {
            id = _withdrawalQueue[i];
            withdrawal = _queuedWithdrawal[id];

            assets = _convertToAssets({shares: withdrawal.shares, allocatedAssets: allocatedAssets});

            delete  _queuedWithdrawal[id];

            _queuedShares[withdrawal.account] -= withdrawal.shares;

            _burn(withdrawal.account, withdrawal.shares);

            usdc.safeTransfer(withdrawal.account, assets);

            emit WithdrawalProcessed(id, withdrawal.account, withdrawal.shares, assets);
        }

        _dequeueBatch(num);
    }

    function grantAdminRole(address account) external onlyOwner {
        _grantRoles(account, ADMIN_ROLE);
        emit AdminRoleGranted(account);
    }

    function revokeAdminRole(address account) external onlyOwner {
        _removeRoles(account, ADMIN_ROLE);
        emit AdminRoleRevoked(account);
    }

    function approveOperator(address operator) external onlyOwner {
        if (!hasAllRoles(operator, ADMIN_ROLE)) revert InvalidOperator();

        IOperatorPanel(perpManager).approveOperator({
            account: address(this),
            operator: operator,
            roles: 1 << uint256(PerpsOperatorRoles.ADMIN)
        });
    }

    function disapproveOperator(address operator) external onlyOwner {
        IOperatorPanel(perpManager).disapproveOperator({
            account: address(this),
            operator: operator,
            roles: 1 << uint256(PerpsOperatorRoles.ADMIN)
        });
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           PERP MANAGER HOOK
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function addSubaccount(uint256 subaccount) external onlyPerpManager {
        _subaccounts.add(subaccount);
    }

    function removeSubaccount(uint256 subaccount) external onlyPerpManager {
        _subaccounts.remove(subaccount);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                GETTERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function totalAssets() public view override returns (uint256) {
        return usdc.balanceOf(address(this)) + orderbookCollateral() + freeCollateralBalance() + totalAccountValue();
    }

    function totalAccountValue() public view returns (uint256 accountValue) {
        uint256[] memory subaccounts = _subaccounts.values();

        int256 subaccountValue;
        for (uint256 i; i < subaccounts.length; ++i) {
            subaccountValue = IViewPort(perpManager).getAccountValue(address(this), subaccounts[i]);
            if (subaccountValue > 0) accountValue += subaccountValue.abs();
        }
    }

    function orderbookCollateral() public view returns (uint256 collateral) {
        uint256[] memory subaccounts = _subaccounts.values();

        for (uint256 i; i < subaccounts.length; ++i) {
            collateral += IViewPort(perpManager).getOrderbookCollateral(address(this), subaccounts[i]);
        }
    }

    function freeCollateralBalance() public view returns (uint256) {
        return IViewPort(perpManager).getFreeCollateralBalance(address(this));
    }

    function getSubaccounts() external view returns (uint256[] memory) {
        return _subaccounts.values();
    }

    function getQueuedWithdrawal(uint256 id) external view returns (Withdrawal memory) {
        return _queuedWithdrawal[id];
    }

    function getQueuedShares(address account) external view returns (uint256) {
        return _queuedShares[account];
    }

    function getWithdrawalQueue() external view returns (uint256[] memory) {
        return _withdrawalQueue;
    }

    function hasAdminRole(address account) external view returns (bool) {
        return hasAllRoles(account, ADMIN_ROLE);
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                           UNUSED 4626 LOGIC
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function previewWithdraw(uint256) public pure override returns (uint256 assets) {
        return 0;
    }

    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    function maxRedeem(address) public pure override returns (uint256) {
        return 0;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                HELPERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _afterTokenTransfer(address from, address, uint256) internal view override {
        if (balanceOf(from) < _queuedShares[from]) revert InsufficientBalance();
    }

    function _dequeue(uint256 id) internal {
        uint256[] memory withdrawalQueue = _withdrawalQueue;
        uint256 length = withdrawalQueue.length;

        uint256[] memory newQueue = new uint256[](length - 1);

        uint256 idx;
        for (uint256 i; i < length; ++i) {
            if (withdrawalQueue[i] != id) newQueue[idx++] = withdrawalQueue[i];
        }

        _withdrawalQueue = newQueue;
    }

    function _dequeueBatch(uint256 num) internal {
        uint256[] memory withdrawalQueue = _withdrawalQueue;

        _withdrawalQueue = withdrawalQueue.slice(num, withdrawalQueue.length);
    }

    /// @dev copied from ERC4626, assuming virtual shares is true & _decimalOffset is 0
    function _convertToAssets(uint256 shares, uint256 allocatedAssets) public view virtual returns (uint256 assets) {
        return shares.fullMulDiv(usdc.balanceOf(address(this)) + allocatedAssets + 1, totalSupply() + 1);
    }

    function _assertAdmin() internal view {
        if (!hasAllRoles(msg.sender, ADMIN_ROLE) && msg.sender != owner()) revert NotAdmin();
    }
}
