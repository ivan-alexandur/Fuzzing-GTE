// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@solady/tokens/ERC20.sol";

import {ILaunchpad} from "./interfaces/ILaunchpad.sol";

contract LaunchToken is ERC20 {
    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                         ERRORS AND EVENTS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev sig: 0xd386ef3e
    error BadAuth();
    /// @dev sig: 0x9ca33913
    error TransfersDisabledWhileBonding();
    /// @dev sig: 0xe97e187c
    error TotalSupplyExceedsMaxShares();

    /// @dev event-sig:
    event TransfersUnlocked(uint256 timestamp, uint256 eventNonce);
    event FeeShareIncreased(address indexed account, uint256 amount, uint256 eventNonce);
    event FeeShareDecreased(address indexed account, uint256 amount, uint256 eventNonce);
    event FeeShareConcluded(uint256 timestamp, uint256 eventNonce);

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            CUSTOM STATE
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @dev The abi version of this impl so the indexer can handle event-changing upgrades
    uint256 public constant ABI_VERSION = 1;

    address public immutable launchpad;
    address public immutable gteRouter;
    string private _name;
    string private _symbol;
    string private _mediaURI;

    bool public unlocked;
    uint256 public eventNonce;
    uint256 public totalFeeShare;
    mapping(address => uint256) public bondingShare;

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                             CONSTRUCTOR
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    // slither-disable-next-line missing-zero-check
    constructor(string memory name_, string memory symbol_, string memory mediaUri_, address gteRouter_) {
        _name = name_;
        _symbol = symbol_;
        _mediaURI = mediaUri_;
        gteRouter = gteRouter_;
        launchpad = msg.sender;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                                MODIFIERS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    modifier onlyLaunchpad() {
        if (msg.sender != launchpad) revert BadAuth();
        _;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            PUBLIC VIEWS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Implements solady token name
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Implements solady token symbol
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Additional data field for token image
    function mediaURI() public view returns (string memory) {
        return _mediaURI;
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                              OWNER-ONLY
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    /// @notice Entrypoint for launchpad (deployer) to unlock transfers
    function unlock() external onlyLaunchpad {
        unlocked = true;
        emit TransfersUnlocked(block.timestamp, _incEventNonce());
    }

    /// @notice Entrypoint for launchpad to mint token (launchpad only calls once)
    function mint(uint256 amount) external onlyLaunchpad {
        _mint(launchpad, amount);

        if (totalSupply() > type(uint96).max) revert TotalSupplyExceedsMaxShares();
    }

    /*▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
                            INTERNAL ASSERTIONS
    ▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀*/

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (!unlocked && from != launchpad && to != launchpad && to != gteRouter) {
            revert TransfersDisabledWhileBonding();
        }

        if (!unlocked) {
            if (from != launchpad && to != launchpad && to != gteRouter) revert TransfersDisabledWhileBonding();

            if (from == launchpad && to != launchpad) _increaseFeeShares(to, amount);
            else if (to != launchpad && to != gteRouter) revert TransfersDisabledWhileBonding();
        }

        if (from != launchpad) _decreaseFeeShares(from, amount);
    }

    function _increaseFeeShares(address account, uint256 amount) internal {
        if (amount == 0 || account == address(0)) return;

        emit FeeShareIncreased(account, amount, _incEventNonce());

        unchecked {
            totalFeeShare += amount;
            bondingShare[account] += amount;
        }

        ILaunchpad(launchpad).increaseStake(account, uint96(amount));
    }

    function _decreaseFeeShares(address account, uint256 amount) internal {
        uint256 share = bondingShare[account];
        if (share == 0 || account == address(0)) return;

        amount = amount > share ? share : amount;

        emit FeeShareDecreased(account, amount, _incEventNonce());

        unchecked {
            totalFeeShare -= amount;
            bondingShare[account] -= amount;
        }

        if (totalFeeShare == 0 && !unlocked) _endRewards();

        ILaunchpad(launchpad).decreaseStake(account, uint96(amount));
    }

    /// @dev Hook to end rewards program for this base token if no more pre-bonding shares exist
    function _endRewards() internal {
        ILaunchpad(launchpad).endRewards();

        emit FeeShareConcluded(block.timestamp, _incEventNonce());
    }

    function _incEventNonce() internal returns (uint256 nonce) {
        nonce = eventNonce;
        eventNonce++;
    }
}
