// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/UniswapV3LP.sol";
import "../src/LPToken.sol";
import "../src/Constant.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IERC20Extended is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
}

/**
 * Based off of https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525
 *
 *  TODO build test case for decreaseLiquidity from https://arbiscan.io/tx/0x081b152f215a5c2a637f7a467e10a1675951424a0b82ccba59783eea684226c8
 */
contract LPTest is Test {
    //Copied from IERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    //Copied from IUniswapV3PoolEvents
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    UniswapV3LP public uniswapv3lp;

    uint256 amount0ToMint = 16027151935214508; //$ 0.0amount0ToMint
    uint256 amount1ToMint = 10000; // $0.01
    uint256 slippage = 500;

    address token0 = DAI;
    address token1 = USDC;
    uint24 fee = 500;

    INonfungiblePositionManager.MintParams params;
    IUniswapV3Pool pool;
    LPToken lpToken;

    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Set to one from alchemy pointing to arbitrum mainnet
        vm.createSelectFork(vm.envString("RPC_URL"), 61253298);

        uniswapv3lp = new UniswapV3LP(Constant.NON_FUNGIBLE_POS_MGR, Constant.UNISWAP_V3_FACTORY);

        pool = IUniswapV3Pool(IUniswapV3Factory(Constant.UNISWAP_V3_FACTORY).getPool(token0, token1, fee));
        int24 tickSpacing = pool.tickSpacing();
        (, int24 currentTick,,,,,) = pool.slot0();

        tickLower = (currentTick / tickSpacing) * tickSpacing;
        tickLower -= tickSpacing; //-276320 User of this txn went an extra tick space lower
        tickUpper = (currentTick / tickSpacing) * tickSpacing + tickSpacing; //-276310

        // currtTick: -276323
        // tickLower: -276330
        // tickUpper: -276310

        params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0, //Will get filled in with slippage calc
            amount1Min: 0, //Will get filled in with slippage calc
            recipient: address(uniswapv3lp),
            deadline: 1676494183 // User chose something waaaay out into the future
        });

        lpToken = new LPToken("lpName", "lpSymbol");
        lpToken.transferOwnership(address(uniswapv3lp)); //TODO need to do for deployment!

        //Setup balances.  foundry rocks this is insane
        {
            // For dai we can mint if we fake out the msg.sender as authorized
            address daiAuth = address(0x10E6593CDda8c58a1d0f14C5164B376352a55f2F); //Found by searching event log for Rely's topic hash (0xdd0e34038ac38b2a1ce960229778ac48a8719bc900b6c4f8d0475c6e8b385a60) at https://arbiscan.io/address/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1#events
            vm.prank(daiAuth);
            IERC20Extended(DAI).mint(address(this), amount0ToMint);
            IERC20Extended(DAI).increaseAllowance(address(uniswapv3lp), amount0ToMint); //TODO we need to do this in prod!

            // For USDC we can send from contract's supply to us directly
            vm.startPrank(USDC);
            IERC20Extended(USDC).increaseAllowance(address(this), amount1ToMint);
            IERC20Extended(USDC).transfer(address(this), amount1ToMint);
            vm.stopPrank();
            IERC20Extended(USDC).increaseAllowance(address(uniswapv3lp), amount1ToMint); //TODO we need to do this in prod!
        }
    }

    function testMint() public {
        vm.expectEmit(true, true, true, true, address(DAI));
        emit Transfer(address(this), address(uniswapv3lp), amount0ToMint);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(this), address(uniswapv3lp), 10000);

        //TODO validate ALL Transfer and approval events to tighten this test

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            uniswapv3lp.mintNewPosition(params, lpToken, slippage);

        // These numbers tie out with IncreaseLiquidity event from https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525  <-- TODO validate this event
        assertEq(tokenId, 329324);
        assertEq(uint256(liquidity), 26035825305594);
        assertEq(amount0, amount0ToMint);
        assertEq(amount1, 10000);
    }

    function testMintSlippage() public {
        uint256 belowSlippage0 = (amount0ToMint * (1e5 - slippage) / 1e5) - 1;
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector),
            abi.encode(belowSlippage0, amount1ToMint)
        );
        vm.expectRevert(bytes("Price slippage check"));
        uniswapv3lp.mintNewPosition(params, lpToken, slippage);

        uint256 belowSlippage1 = (amount1ToMint * (1e5 - slippage) / 1e5) - 1;
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector),
            abi.encode(amount0ToMint, belowSlippage1)
        );
        vm.expectRevert(bytes("Price slippage check"));
        uniswapv3lp.mintNewPosition(params, lpToken, slippage);
    }

    function testMintThenDecreaseLiquidity() public {
        vm.expectEmit(true, true, true, true, address(DAI));
        emit Transfer(address(this), address(uniswapv3lp), amount0ToMint);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(this), address(uniswapv3lp), 10000);

        //TODO validate ALL Transfer and approval events to tighten this test

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            uniswapv3lp.mintNewPosition(params, lpToken, slippage);

        // These numbers tie out with IncreaseLiquidity event from https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525  <-- TODO validate this event
        assertEq(tokenId, 329324);
        assertEq(uint256(liquidity), 26035825305594);
        assertEq(amount0, amount0ToMint);
        assertEq(amount1, 10000);

        uint128 decreaseLiquidity = liquidity / 2;
        {
            //TODO validate ALL Transfer and approval events to tighten this test

            vm.expectEmit(true, true, true, true, Constant.UNISWAP_V3_POOL);
            emit Burn(
                address(Constant.NON_FUNGIBLE_POS_MGR),
                tickLower,
                tickUpper,
                decreaseLiquidity,
                amount0ToMint / 2 - 1,
                amount1ToMint / 2 - 1
                );

            (amount0, amount1) = uniswapv3lp.decreaseLiquidity(tokenId, decreaseLiquidity, slippage);
        }
        assertEq(amount0, amount0ToMint / 2 - 1);
        assertEq(amount1, amount1ToMint / 2 - 1);
    }

    function testDecreaseLiquiditySlippage() public {
        vm.expectEmit(true, true, true, true, address(DAI));
        emit Transfer(address(this), address(uniswapv3lp), amount0ToMint);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(this), address(uniswapv3lp), 10000);

        //TODO validate ALL Transfer and approval events to tighten this test

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            uniswapv3lp.mintNewPosition(params, lpToken, slippage);

        // These numbers tie out with IncreaseLiquidity event from https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525  <-- TODO validate this event
        assertEq(tokenId, 329324);
        assertEq(uint256(liquidity), 26035825305594);
        assertEq(amount0, amount0ToMint);
        assertEq(amount1, amount1ToMint);

        uint128 decreaseLiquidity = liquidity / 2;
        {
            vm.mockCall(
                address(pool),
                abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector),
                abi.encode(7973508087769216 - 1, 4974 - 1)
            );
            vm.expectRevert(bytes("Price slippage check"));
            (amount0, amount1) = uniswapv3lp.decreaseLiquidity(tokenId, decreaseLiquidity, slippage);
        }
    }
}
