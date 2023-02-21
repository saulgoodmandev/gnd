
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';


contract GND is ERC20("GND", "GND"), Ownable {
    using SafeMath for uint256;

    address public stakingContract;
    address public xGND;

    constructor(address _stakingContract) {
        stakingContract = _stakingContract;
        _mint(stakingContract, 18000e18);
    }

 
    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }

    function mint(address recipient, uint256 _amount) external {
        require(msg.sender == stakingContract || msg.sender == xGND);
        _mint(recipient, _amount);

    }

    function updateMinters(address _xGND, address _staking) external onlyOwner {
        xGND = _xGND;
        stakingContract = _staking;
    }

}