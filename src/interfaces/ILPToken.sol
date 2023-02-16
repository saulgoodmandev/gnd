// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPToken is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}