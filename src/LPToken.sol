// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILPToken.sol";

contract LPToken is ERC20("TODO", "TODO"), ILPToken, Ownable, ReentrancyGuard {
    uint256 public _lpShares;
    uint256 public _amount0;
    uint256 public _amount1;

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }

    function set(uint256 lpShares, uint256 amount0, uint256 amount1) public {
        _lpShares = lpShares;
        _amount0 = amount0;
        _amount1 = amount1;
    }
}
