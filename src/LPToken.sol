// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./interfaces/ILPToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LPToken is ERC20, ILPToken, Ownable{
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function burn(address from, uint256 amount)  external override onlyOwner {
        _burn(from, amount);
    }

    function mint(address recipient, uint256 amount) external override onlyOwner {
        _mint(recipient, amount);
    }
}
