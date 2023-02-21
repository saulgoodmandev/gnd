// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "forge-std/Script.sol";
import "../src/UniswapV3LP.sol";
import "../src/GND.sol";
import "../src/xGND.sol";
import "../src/xGNDstaking.sol";
import "../src/gmdUSD.sol";
import "../src/Constant.sol";

contract UniswapV3lpScript is Script {
    UniswapV3LP public _uniswapv3lp;
    gmdUSD public _gmdUSD;
    GND public _gnd;
    
    xGND public _xGND;
    xGNDstaking public _xGNDstaking;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        _uniswapv3lp = new UniswapV3LP(Constant.NON_FUNGIBLE_POS_MGR, Constant.UNISWAP_V3_FACTORY);
        _gmdUSD = new gmdUSD();
        _gnd = new GND();
        _gnd.transferOwnership(address(_uniswapv3lp));
        _xGNDstaking = new xGNDstaking(0, 0, 0);
        _xGND = new xGND(address(_gnd), address(_xGNDstaking));


        vm.stopBroadcast();
    }
}
