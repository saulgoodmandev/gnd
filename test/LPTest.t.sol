// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/UniswapV3LP.sol";
import "../src/LPToken.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IERC20Extended is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
}

/**
 * Based off of https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525
 */
contract LPTest is Test {
    //Copied from IERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    //https://app.uniswap.org/#/add/0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1/0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8/500?maxPrice=1.001153
    address public constant nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public constant univ3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant UNISWAP_V3_POOL = 0xd37Af656Abf91c7f548FfFC0133175b5e4d3d5e6;
    // address public constant gmdUSDC = 0x3DB4B7DA67dd5aF61Cb9b3C70501B1BdB24b2C22;
    // univ3pool dai/usdc 500 fee: 0xd37Af656Abf91c7f548FfFC0133175b5e4d3d5e6
    UniswapV3LP public uniswapv3lp;

    uint256 amount0ToMint = 16027151935214508; //$ 0.016027151935214508
    uint256 amount1ToMint = 10000; // $0.01
    uint256 slippage = 500;

    address token0 = DAI;
    address token1 = USDC;
    uint24 fee = 500;

    INonfungiblePositionManager.MintParams params;
    IUniswapV3Pool pool;
    LPToken lpToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"), 61253298);

        uniswapv3lp = new UniswapV3LP(nonfungiblePositionManager, univ3Factory);

        pool = IUniswapV3Pool(IUniswapV3Factory(univ3Factory).getPool(token0, token1, fee));
        int24 tickSpacing = pool.tickSpacing();
        (, int24 currentTick,,,,,) = pool.slot0();

        int24 tickLower = (currentTick / tickSpacing) * tickSpacing;
        tickLower -= tickSpacing; //-276320 User of this txn went an extra tick space lower
        int24 tickUpper = (currentTick / tickSpacing) * tickSpacing + tickSpacing; //-276310

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

        lpToken = new LPToken("lpDAIUSD", "lpDAIUSD");
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
        emit Transfer(address(this), address(uniswapv3lp), 16027151935214508);
        vm.expectEmit(true, true, true, true, address(USDC));
        emit Transfer(address(this), address(uniswapv3lp), 10000);

        //TODO validate ALL Transfer and approval events to tighten this test

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            uniswapv3lp.mintNewPosition(params, lpToken, slippage);

        // These numbers tie out with IncreaseLiquidity event from https://arbiscan.io/tx/0x0e98dc460c6445f745e2e637ddca6be72767914ca9d4cba9b838f84138622525  <-- TODO validate this event
        assertEq(tokenId, 329324);
        assertEq(uint256(liquidity), 26035825305594);
        assertEq(amount0, 16027151935214508);
        assertEq(amount1, 10000);
    }

    function testSlippage() public {
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
}
