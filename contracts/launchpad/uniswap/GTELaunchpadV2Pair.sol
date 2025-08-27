// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@gte-univ2-core/interfaces/IUniswapV2Pair.sol";
import "@gte-univ2-core/UniswapV2ERC20.sol";
import "@gte-univ2-core/libraries/Math.sol";
import "@gte-univ2-core/libraries/UQ112x112.sol";
import "@gte-univ2-core/interfaces/IERC20.sol";
import "@gte-univ2-core/interfaces/IUniswapV2Factory.sol";
import "@gte-univ2-core/interfaces/IUniswapV2Callee.sol";

import "../interfaces/IDistributor.sol";
import "./interfaces/IGTELaunchpadV2Pair.sol";

// import "forge-std/Console.sol";

contract GTELaunchpadV2Pair is IUniswapV2Pair, IGTELaunchpadV2Pair, UniswapV2ERC20 {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    event RewardsPoolDeactivated();
    event LaunchpadFeesAccrued(uint112 fee0, uint112 fee1);
    event LaunchpadFeesCollected(uint256 collected0, uint256 collected1);
    event LaunchpadFeesLastAccrued(uint112 fee0, uint112 fee1);

    uint256 public constant REWARDS_FEE_SHARE = 1;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256(bytes("approve(address,uint256)")));

    // If the launchpad is non 0, then this pool will accumulate a share of swap fees that can be claimed
    address public launchpadLp;
    address public launchpadFeeDistributor;

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint112 public accruedLaunchpadFee0;
    uint112 public accruedLaunchpadFee1;

    uint256 public rewardsPoolActive = 1;

    uint256 private unlocked = 1;

    modifier lock() {
        if (unlocked != 1) revert("UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getAccruedLaunchpadFees() public view returns (uint112, uint112, uint32) {
        return (accruedLaunchpadFee0, accruedLaunchpadFee1, blockTimestampLast);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
        if (!success || !(data.length == 0 || abi.decode(data, (bool)))) revert("UniswapV2: TRANSFER_FAILED");
    }

    function _safeApprove(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(APPROVE_SELECTOR, to, value));
        if (!success || !(data.length == 0 || abi.decode(data, (bool)))) revert("UniswapV2: APPROVAL_FAILED");
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, address _launchpadLp, address _launchpadFeeDistributor)
        external
    {
        if (msg.sender != factory) revert("UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
        launchpadLp = _launchpadLp;
        launchpadFeeDistributor = _launchpadFeeDistributor;
        rewardsPoolActive = 1;
    }

    function endRewardsAccrual() external {
        if (msg.sender != launchpadFeeDistributor) revert("GTEUniV2: FORBIDDEN");

        // There are no more shares, so prevent distribution and accrual of any remaining rewards
        delete accruedLaunchpadFee0;
        delete accruedLaunchpadFee1;
        delete rewardsPoolActive;

        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1,
            uint112(0),
            uint112(0)
        );

        emit RewardsPoolDeactivated();
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1,
        uint112 newLaunchpadFee0,
        uint112 newLaunchpadFee1
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert("UniswapV2: OVERFLOW");

        // New accrued fees must AT LEAST equal existing undistributed fees so that the Sync can be accurate
        uint112 totalLaunchpadFee0 = accruedLaunchpadFee0 + newLaunchpadFee0;
        uint112 totalLaunchpadFee1 = accruedLaunchpadFee1 + newLaunchpadFee1;

        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;

            if (launchpadFeeDistributor > address(0)) {
                if (totalLaunchpadFee0 | totalLaunchpadFee1 > 0) {
                    delete accruedLaunchpadFee0;
                    delete accruedLaunchpadFee1;
                    _distributeLaunchpadFees(totalLaunchpadFee0, totalLaunchpadFee1);
                }
            }
        } else if (launchpadFeeDistributor > address(0) && newLaunchpadFee0 | newLaunchpadFee1 > 0) {
            accruedLaunchpadFee0 = totalLaunchpadFee0;
            accruedLaunchpadFee1 = totalLaunchpadFee1;
            emit LaunchpadFeesAccrued(newLaunchpadFee0, newLaunchpadFee1);
        }

        // Balances contain both accrued and new launchpad fees earned this tx
        // as balance is called before any fee distributions, so subtract the total
        reserve0 = _reserve0 = uint112(balance0) - totalLaunchpadFee0;
        reserve1 = _reserve1 = uint112(balance1) - totalLaunchpadFee1;

        blockTimestampLast = blockTimestamp;
        emit Sync(_reserve0, _reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0).mul(_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint256 denominator = rootK.mul(5).add(rootKLast);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        if (liquidity == 0) revert("UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1, uint112(0), uint112(0));
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) revert("UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1, uint112(0), uint112(0));
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        if (amount0Out == 0 && amount1Out == 0) revert("UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert("UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            if (to == _token0 || to == _token1) revert("UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert("UniswapV2: INSUFFICIENT_INPUT_AMOUNT");

        {
            // scope for reserve{0,1}Adjusted and launchpadFee{0,1}, avoids stack too deep errors
            uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));

            if (balance0Adjusted.mul(balance1Adjusted) < uint256(_reserve0).mul(_reserve1).mul(1000 ** 2)) {
                revert("UniswapV2: K");
            }

            (uint112 launchpadFee0, uint112 launchpadFee1) = launchpadFeeDistributor > address(0)
                && rewardsPoolActive > 0 ? _getLaunchpadFees(amount0In, amount1In) : (uint112(0), uint112(0));

            _update(balance0, balance1, _reserve0, _reserve1, launchpadFee0, launchpadFee1);
        }

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _getLaunchpadFees(uint256 amount0In, uint256 amount1In)
        internal
        view
        returns (uint112 fee0, uint112 fee1)
    {
        // Only swap fees that represent the launchpad's share of the LP supply should accrue towards unclaimed launchpad fees.
        // MINIMUM_LIQUIDITY is permanently locked to address(0) when liquidity is first added by the launchpad.
        // Therefore, we add it back here so that the fee share math represents the whole of *initial* liquidity added,
        // not just the launchpad's slightly lower actual lp balance
        uint256 totalLpBal = this.totalSupply();
        uint256 launchpadLpBal = this.balanceOf(launchpadLp) + MINIMUM_LIQUIDITY;

        if (amount0In > 0) fee0 = uint112(amount0In.mul(REWARDS_FEE_SHARE).mul(launchpadLpBal) / (totalLpBal * 1000));
        if (amount1In > 0) fee1 = uint112(amount1In.mul(REWARDS_FEE_SHARE).mul(launchpadLpBal) / (totalLpBal * 1000));

        return (fee0, fee1);
    }

    function _distributeLaunchpadFees(uint112 fee0, uint112 fee1) internal {
        if ((fee0 | fee1) > 0) {
            address _token0 = token0;
            address _token1 = token1;
            address distributor = launchpadFeeDistributor;

            // Since only pairs created by the launchpad can accrue fee tracking, the tokens are trusted
            if (fee0 > 0) _safeApprove(_token0, distributor, uint256(fee0));
            if (fee1 > 0) _safeApprove(_token1, distributor, uint256(fee1));

            IDistributor(distributor).addRewards(_token0, _token1, uint128(fee0), uint128(fee1));

            emit LaunchpadFeesCollected(fee0, fee1);
        }
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0 + accruedLaunchpadFee0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1 + accruedLaunchpadFee1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1,
            uint112(0),
            uint112(0)
        );
    }
}
