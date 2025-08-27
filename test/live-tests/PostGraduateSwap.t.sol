// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IUniswapV2RouterMinimal} from "contracts/launchpad/interfaces/IUniswapV2RouterMinimal.sol";
import {IUniswapV2FactoryMinimal} from "contracts/launchpad/interfaces/IUniswapV2FactoryMinimal.sol";
import {IDistributor} from "contracts/launchpad/interfaces/IDistributor.sol";

import {ERC1967Factory} from "@solady/utils/ERC1967Factory.sol";
import {Launchpad} from "contracts/launchpad/Launchpad.sol";
import {LaunchpadLPVault} from "contracts/launchpad/LaunchpadLPVault.sol";
import {GTERouter} from "contracts/router/GTERouter.sol";
import {Create2} from "@openzeppelin/utils/Create2.sol";

import {MockDistributor} from "../mocks/MockDistributor.sol";

import {WETH} from "solady/tokens/WETH.sol";

contract PostGraduateTest is Test {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    ERC1967Factory factory;
    IUniswapV2RouterMinimal uniV2Router;
    address distributor;
    GTERouter gteRouter;
    Launchpad launchpad;
    LaunchpadLPVault launchpadLPVault;
    address clobManager;
    address launchToken;
    WETH weth;

    address deployer;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        factory = ERC1967Factory(vm.envOr("GTE_FACTORY_TESTNET", address(0)));
        uniV2Router = IUniswapV2RouterMinimal(vm.envOr("UNIV2_VANILLA_ROUTER_TESTNET", address(0)));
        gteRouter = GTERouter(payable(vm.envOr("GTE_ROUTER_TESTNET", address(0))));
        launchpad = Launchpad(vm.envOr("GTE_LAUNCHPAD_TESTNET", address(0)));
        launchpadLPVault = LaunchpadLPVault(vm.envOr("GTE_LAUNCHPAD_LP_VAULT_TESTNET", address(0)));
        deployer = vm.envOr("DEPLOYER", address(0));
        weth = WETH(payable(vm.envOr("WETH_TESTNET", address(0))));
        clobManager = vm.envOr("CLOB_MANAGER_TESTNET", address(0));

        distributor = address(new MockDistributor());

        if (address(launchpad) == address(0)) return;

        vm.createSelectFork("testnet");

        deal(deployer, 100_000_000e18);
    }

    function est_Graduate_SkimDonatedQuote() public {
        if (address(uniV2Router) == address(0)) return;

        address quoteAsset = address(launchpad.currentQuoteAsset());

        address launchpadLogic =
            address(new Launchpad(address(uniV2Router), address(gteRouter), address(0), address(0), distributor));

        vm.startPrank(deployer);
        factory.upgrade(address(launchpad), launchpadLogic);

        deal(quoteAsset, deployer, 50_000_000 ether);

        quoteAsset.safeApprove(address(launchpad), type(uint256).max);

        IUniswapV2FactoryMinimal uniV2Factory = IUniswapV2FactoryMinimal(uniV2Router.factory());
        uint256 fee = launchpad.launchFee();
        address poolExistsToken = launchpad.launch{value: fee}("", "", "");
        address poolNoExistsToken = launchpad.launch{value: fee}("", "", "");

        vm.label(poolExistsToken, "PoolExistsToken");
        vm.label(poolNoExistsToken, "PoolNoExistsToken");

        uint256 bondingSupply = launchpad.currentBondingCurve().bondingSupply(poolExistsToken);

        // Pool already exists after being donated to
        bytes memory newInitCode = hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";
        launchpad.updateInitCodeHash(newInitCode);

        address poolNoExistsPair = pairFor(address(uniV2Factory), newInitCode, poolNoExistsToken, address(weth));

        // Donate 10 weth to the bonding pair before it exists
        quoteAsset.safeTransfer(poolNoExistsPair, 10 ether);

        // address launchpadOwner = launchpad.owner();

        // // // Expect the donated weth to be skimmed back to launchpad owner
        // vm.expectEmit(quoteAsset);
        // emit Transfer(poolNoExistsPair, launchpadOwner, 10 ether);
        // launchpad.buy(deployer, poolNoExistsToken, deployer, bondingSupply, type(uint256).max);

        // bytes memory uniV2InitCodeHash = launchpad.uniV2InitCodeHash();

        // // Same thing as above but someone created the pair with 0 liq
        // address pair = uniV2Factory.createPair(poolExistsToken, address(weth));
        // address poolExistsPair = pairFor(address(uniV2Factory), newInitCode, poolExistsToken, address(weth));

        // assertEq(pair, poolExistsPair, "created and computer pairs differ, incorrect univ2 factory initcode hash");

        // quoteAsset.safeTransfer(poolExistsPair, 10 ether);

        // vm.expectEmit(quoteAsset);
        // emit Transfer(poolExistsPair, launchpadOwner, 10 ether);
        // launchpad.buy(deployer, poolExistsToken, deployer, bondingSupply, type(uint256).max);
    }

    function est_PostGraduateSwap_SuccessfulAMMSwap() public {
        if (address(uniV2Router) == address(0)) return;

        address quoteAsset = address(launchpad.currentQuoteAsset());

        address launchpadLogic =
            address(new Launchpad(address(uniV2Router), address(gteRouter), clobManager, address(0), distributor));

        vm.startPrank(deployer);
        factory.upgrade(address(launchpad), launchpadLogic);
        bytes memory newInitCode = hex"d6489e3db3f3ad8088fd39565767dff2b095a18db473ff5fb869b9ccd443acfa";
        launchpad.updateInitCodeHash(newInitCode);

        deal(quoteAsset, deployer, 50_000 ether);

        vm.startPrank(deployer);
        quoteAsset.safeApprove(address(gteRouter), type(uint256).max);
        quoteAsset.safeApprove(address(launchpad), type(uint256).max);

        uint256 fee = launchpad.launchFee();
        launchToken = launchpad.launch{value: fee}("TestToken", "TT", "https://test.com");

        uint256 bondedBase = launchpad.currentBondingCurve().bondingSupply(launchToken);
        uint256 bondedQuote = launchpad.quoteQuoteForBase(launchToken, bondedBase, true);

        uint256 baseLiquidity = launchpad.currentBondingCurve().totalSupply(launchToken) - bondedBase;

        uint256 ammBase = 100_000_000e18;
        uint256 ammQuote = uniV2Router.getAmountIn(ammBase, bondedQuote, baseLiquidity);

        uint256 tokenBefore = launchToken.balanceOf(deployer);
        uint256 quoteBefore = quoteAsset.balanceOf(deployer);

        gteRouter.launchpadBuy(launchToken, bondedBase + ammBase, quoteAsset, bondedQuote + ammQuote + 10e18);

        uint256 tokenAfter = launchToken.balanceOf(deployer);
        uint256 quoteAfter = quoteAsset.balanceOf(deployer);

        assertEq(tokenAfter - tokenBefore, bondedBase + ammBase);
        assertEq(quoteBefore - quoteAfter, bondedQuote + ammQuote);
    }

    // TODO move these all to one place lol
    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address fact, bytes memory initCodeHash, address tokenA, address tokenB)
        internal
        pure
        returns (address pair)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes32 codeHash = bytes32(initCodeHash);

        pair = Create2.computeAddress(salt, codeHash, fact);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }
}
