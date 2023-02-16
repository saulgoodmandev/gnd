// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILPToken.sol";
import "./LPToken.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

/**
 * Based off of https://github.com/Uniswap/docs/blob/main/examples/smart-contracts/LiquidityExamples.sol
 */
contract UniswapV3LP is IERC721Receiver, Ownable {

    INonfungiblePositionManager public immutable _posMgr;
    IUniswapV3Factory public immutable _univ3Factory;

    // @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    // @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    mapping(uint256 => ILPToken) public lps;

    constructor(address posMgr, address univ3Factory) {
        _posMgr = INonfungiblePositionManager(posMgr);
        _univ3Factory = IUniswapV3Factory(univ3Factory);
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        require(msg.sender == address(_posMgr), "not a univ3 nft");
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (,, address token0, address token1,,,, uint128 liquidity,,,,) = _posMgr.positions(tokenId);
        // set the owner and data for position
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }

    function slippagify(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        require(slippage >= 0 && slippage <= 1e5, "not in range");
        return amount * (1e5 - slippage) / 1e5;
    }

    /**
     * @notice Calls the mint function defined in periphery, mints the same amount of each token.
     *  For this example we are providing 1000 DAI and 1000 USDC in liquidity
     *  @param params The values for tickLower and tickUpper may not work for all tick spacings.
     *  Setting amount0Min and amount1Min to 0 is unsafe.
     *  @return tokenId The id of the newly minted ERC721
     *  @return liquidity The amount of liquidity for the position
     *  @return amount0 The amount of token0
     *  @return amount1 The amount of token1
     */
    function mintNewPosition(INonfungiblePositionManager.MintParams memory params, LPToken lpToken, uint256 slippage)
        external
        onlyOwner //TODO remove onlyOwner?
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(_univ3Factory.getPool(params.token0, params.token1, params.fee));

        // {
            
        //     uint256 lpShares;
        //     (lpShares, amount0, amount1) = pool.computeLpShares(
        //         true,
        //         params.amount0Desired,
        //         params.amount1Desired,
        //         IERC20(params.token0).balanceOf(msg.sender),
        //         IERC20(params.token1).balanceOf(msg.sender),
        //         lpToken.totalSupply(),
        //         ticks
        //     );
        //     console.log("lpShares: ", lpShares);
        //     console.log("amount0: ", amount0);
        //     console.log("amount1: ", amount1);
        // }
        // transfer tokens to contract
        TransferHelper.safeTransferFrom(params.token0, msg.sender, address(this), params.amount0Desired);
        TransferHelper.safeTransferFrom(params.token1, msg.sender, address(this), params.amount1Desired);

        // Approve the position manager
        TransferHelper.safeApprove(params.token0, address(_posMgr), params.amount0Desired);
        TransferHelper.safeApprove(params.token1, address(_posMgr), params.amount1Desired);

        // Note that the pool must already be created and initialized in order to mint
        params.amount0Min = slippagify(amount0, slippage);
        params.amount1Min = slippagify(amount1, slippage);

        (tokenId, liquidity, amount0, amount1) = _posMgr.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);
        //record lp token
        lps[tokenId] = lpToken;
        // Remove allowance and refund in both assets.
        if (amount0 < params.amount0Desired) {
            TransferHelper.safeApprove(params.token0, address(_posMgr), 0);
            uint256 refund0 = params.amount0Desired - amount0;
            TransferHelper.safeTransfer(params.token0, msg.sender, refund0);
        }

        if (amount1 < params.amount1Desired) {
            TransferHelper.safeApprove(params.token1, address(_posMgr), 0);
            uint256 refund1 = params.amount1Desired - amount1;
            TransferHelper.safeTransfer(params.token1, msg.sender, refund1);
        }
        lpToken.mint(msg.sender, liquidity);
    }

    /**
     * @notice Collects the fees associated with provided liquidity
     * @dev The contract must hold the erc721 token before it can collect fees
     * @param tokenId The id of the erc721 token
     * @return amount0 The amount of fees collected in token0
     * @return amount1 The amount of fees collected in token1
     */
    function collectFees(uint256 tokenId) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit
        // set amount0Max and amount1Max to type(uint128).max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = _posMgr.collect(params);

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees back to owner
        _sendToOwner(tokenId, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    /**
     * @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
     * @param tokenId The id of the erc721 token
     * @return amount0 The amount received back in token0
     * @return amount1 The amount returned back in token1
     */
    function decreaseLiquidity(uint256 tokenId, uint128 _liquidity, uint256 slippage)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // caller must be the owner of the NFT
        ILPToken lp = lps[tokenId];
        require(lp.balanceOf(msg.sender) >= _liquidity, "balance too low");

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: _liquidity,
            amount0Min: slippagify(_liquidity * 45 / 100, slippage),
            amount1Min: slippagify(_liquidity * 45 / 100, slippage),
            deadline: block.timestamp
        });

        INonfungiblePositionManager.CollectParams memory params2 = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: 340282366920938463463374607431768211455,
            amount1Max: 340282366920938463463374607431768211455
        });

        (amount0, amount1) = _posMgr.decreaseLiquidity(params);
        _posMgr.collect(params2);

        // send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);

        //burn lp
        lp.burn(msg.sender, _liquidity);
    }

    /**
     * TODO test against https://arbiscan.io/tx/0xc4df8766ba80841f20210c067a27fa853567696495bc438b63001f9ef8c5ee64
     * 
     * @notice Increases liquidity in the current range
     * @dev Pool must be initialized already to add liquidity
     * @param tokenId The id of the erc721 token
     * @param amount0 The amount to add of token0
     * @param amount1 The amount to add of token1
     */
    function increaseLiquidityCurrentRange(uint256 tokenId, uint256 amountAdd0, uint256 amountAdd1, uint256 slippage)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        ILPToken lp = lps[tokenId];
        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountAdd0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amountAdd1);

        TransferHelper.safeApprove(token0, address(_posMgr), amountAdd0);
        TransferHelper.safeApprove(token1, address(_posMgr), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amountAdd0,
            amount1Desired: amountAdd1,
            amount0Min: slippagify(amountAdd0, slippage),
            amount1Min: slippagify(amountAdd1, slippage),
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = _posMgr.increaseLiquidity(params);

        // Remove allowance and refund in both assets.
        if (amount0 < amountAdd0) {
            TransferHelper.safeApprove(token0, address(_posMgr), 0);
            uint256 refund0 = amountAdd0 - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amountAdd1) {
            TransferHelper.safeApprove(token1, address(_posMgr), 0);
            uint256 refund1 = amountAdd1 - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
        lp.mint(msg.sender, liquidity);
    }

    /**
     * @notice Transfers funds to owner of NFT
     * @param tokenId The id of the erc721
     * @param amount0 The amount of token0
     * @param amount1 The amount of token1
     */
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    /**
     * @notice Transfers funds to owner of lptokens
     * @param tokenId The id of the erc721
     * @param amount0 The amount of token0
     * @param amount1 The amount of token1
     */
    function _sendToUser(uint256 tokenId, address user, uint256 amount0, uint256 amount1) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send back to users
        TransferHelper.safeTransfer(token0, user, amount0 * 997 / 1000);
        TransferHelper.safeTransfer(token1, user, amount1 * 997 / 1000);
        //0.3% fees collected when remove liquidity
        TransferHelper.safeTransfer(token0, owner, amount0 * 3 / 1000);
        TransferHelper.safeTransfer(token1, owner, amount1 * 3 / 1000);
    }
}
