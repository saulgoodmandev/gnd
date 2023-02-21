// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract gmUSD is ERC20("gmUSD", "gmUSD"), Ownable , ReentrancyGuard{ 

    address public arbitragor;
    constructor() {
        arbitragor = msg.sender;
    }
   
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    bool public onlyArbitragor = true;

    IERC20 public gmUSDC = IERC20(0x3DB4B7DA67dd5aF61Cb9b3C70501B1BdB24b2C22);
    IERC20 public gDAI = IERC20(0xd85E038593d7A098614721EaE955EC2022B9B91B);


    function updateArbitragor(address _newArbitragor) external onlyOwner {
        arbitragor = _newArbitragor;
    }
   
    function GenesisMint(uint256 _amount, IERC20 _token) external nonReentrant {
        require(totalSupply() <= 150000e18, "max initial supply");
        require(gmUSDC.balanceOf(address(this)) <= 100_000e18, "max gmUSDC");
        require(gDAI.balanceOf(address(this)) <= 50_000e18, "max gDai");
        require(_token == gmUSDC || _token == gDAI, "not pegged token");
        require(_token.balanceOf(msg.sender) >= _amount, "token balance too low");
        uint256 amountOut = _amount;
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, amountOut);
        
    }


    function mint(uint256 _amount, IERC20 _token) external nonReentrant {
        if (onlyArbitragor){
            require(msg.sender == arbitragor, "not arbitragor");
        }
        
        require(_token == gmUSDC || _token == gDAI, "not pegged token");
        require(_token.balanceOf(msg.sender) >= _amount, "token balance too low");
        uint256 amountOut = _amount;
        _mint(msg.sender, amountOut);
        _token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function redeem(uint256 _amount, IERC20 _token) external nonReentrant {
        if (onlyArbitragor){
            require(msg.sender == arbitragor, "not arbitragor");
        }
        require(_token == gmUSDC || _token == gDAI, "not pegged token");
        require(balanceOf(msg.sender) >= _amount, "token balance too low");
        uint256 amountOut = _amount;
        _burn(msg.sender, amountOut);
        _token.safeTransfer(msg.sender, _amount);
    }


}