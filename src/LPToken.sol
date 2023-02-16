// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILPToken.sol";

contract LPToken is ERC20, ILPToken, Ownable, ReentrancyGuard {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }
}
