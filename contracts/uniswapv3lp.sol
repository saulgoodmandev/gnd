// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '../interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import "@openzeppelin/contracts/access/Ownable.sol";


interface LPtoken is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}

contract LiquidityExamples is IERC721Receiver,Ownable {
    INonfungiblePositionManager public constant nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant USDC = 0x3DB4B7DA67dd5aF61Cb9b3C70501B1BdB24b2C22;
    uint24 public constant poolFee = 500;


    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
      
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    mapping(uint256 => LPtoken) public LPs;

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    // Note that the operator is recorded as the owner of the deposited NFT
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), 'not a univ3 nft');
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) =
            nonfungiblePositionManager.positions(tokenId);
        // set the owner and data for position
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }

    function slippagify(uint256 amount, uint256 slippage) internal pure returns(uint256) {
        require(slippage >= 0 && slippage <= 1e5, "not in range");
        return amount*(1e5-slippage)/1e5;
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token.
    /// For this example we are providing 1000 DAI and 1000 USDC in liquidity
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(address t0, address t1, int24 tlow,  int24 tup, uint256 amount0ToMint, uint256 amount1ToMint, uint256 slippage, LPtoken _LPtoken)
        external onlyOwner
        returns  (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
        {

         IUniswapV3Pool pool = IUniswapV3Pool(
            PoolAddress.computeAddress(
                nonfungiblePositionManager.factory(),
                PoolAddress.PoolKey({
                    token0: token0,
                    token1: token1,
                    fee: fee
                })
            )
        );    

        // transfer tokens to contract
        TransferHelper.safeTransferFrom(t0, msg.sender, address(this), amount0ToMint);
        TransferHelper.safeTransferFrom(t1, msg.sender, address(this), amount1ToMint);

        // Approve the position manager
        TransferHelper.safeApprove(t0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(t1, address(nonfungiblePositionManager), amount1ToMint);

        // The values for tickLower and tickUpper may not work for all tick spacings.
        // Setting amount0Min and amount1Min to 0 is unsafe.
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: t0,
                token1: t1,
                fee: poolFee,
                tickLower: tlow,
                tickUpper: tup,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: slippagify(amount0ToMint, slippage),
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Note that the pool must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);
        //record lp token
        LPs[tokenId] = _LPtoken;
        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(t0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(t0, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(t1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(t1, msg.sender, refund1);
        }
        _LPtoken.mint(msg.sender, liquidity);
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectFees(uint256 tokenId) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit
        // set amount0Max and amount1Max to type(uint128).max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees back to owner
        _sendToOwner(tokenId, IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    /// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidity(uint256 tokenId, uint128 _liquidity, uint256 slippage) external returns (uint256 amount0, uint256 amount1) {
        // caller must be the owner of the NFT
        LPtoken lp = LPs[tokenId];
        require(lp.balanceOf(msg.sender) >= _liquidity, "balance too low");

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: _liquidity,
                amount0Min: slippagify(_liquidity*45/100, slippage),
                amount1Min:  slippagify(_liquidity*45/100, slippage),
                deadline: block.timestamp
            });
        
        INonfungiblePositionManager.CollectParams memory params2 =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max:340282366920938463463374607431768211455,
                amount1Max:340282366920938463463374607431768211455
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
        nonfungiblePositionManager.collect(params2);

        // send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
        
        //burn lp 
        lp.burn(msg.sender, _liquidity);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1,
        uint256 slippage
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        LPtoken lp = LPs[tokenId];
        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amountAdd0);
        TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amountAdd1);

        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amountAdd0);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: slippagify(amountAdd0, slippage),
                amount1Min: slippagify(amountAdd1, slippage),
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
        
        // Remove allowance and refund in both assets.
        if (amount0 < amountAdd0) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amountAdd0 - amount0;
            TransferHelper.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < amountAdd1) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amountAdd1 - amount1;
            TransferHelper.safeTransfer(token1, msg.sender, refund1);
        }
        lp.mint(msg.sender, liquidity);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    /// @notice Transfers funds to owner of lptokens
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToUser(
        uint256 tokenId,
        address user,
        uint256 amount0,
        uint256 amount1
    ) private {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send back to users
        TransferHelper.safeTransfer(token0, user, amount0*997/1000);
        TransferHelper.safeTransfer(token1, user, amount1*997/1000);
        //0.3% fees collected when remove liquidity
        TransferHelper.safeTransfer(token0, owner, amount0*3/1000);
        TransferHelper.safeTransfer(token1, owner, amount1*3/1000);
    }


}