// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import "../src/UniswapV3LP.sol";
import "../src/GND.sol";
import "../src/xGND.sol";
import "../src/xGNDstaking.sol";
import "../src/gmUSD.sol";
import "../src/Constant.sol";

contract UniswapV3lpScript is Script {
    UniswapV3LP public _uniswapv3lp;
    gmUSD public _gmUSD;
    GND public _gnd;

    xGND public _xGND;
    xGNDstaking public _xGNDstaking;

    address public newOwner = 0xD70811f1e4992aA051d54e29a04c8925B32fBa7d;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // _uniswapv3lp = new UniswapV3LP(Constant.NON_FUNGIBLE_POS_MGR, Constant.UNISWAP_V3_FACTORY);
        // _uniswapv3lp.transferOwnership(newOwner);
        _gmUSD = new gmUSD();
        // _gmUSD.transferOwnership(newOwner);

        // _xGNDstaking = new xGNDstaking(0, 0, 0);
        // _xGNDstaking.transferOwnership(newOwner);
        // _gnd = new GND(address(_xGNDstaking));
        // _gnd.transferOwnership(address(_uniswapv3lp));

        // _xGND = new xGND(address(_gnd), address(_xGNDstaking));
        // _xGND.transferOwnership(newOwner);

        vm.stopBroadcast();
    }
}
