# gnd

Since https://github.com/Uniswap/v3-core and v3-periphery cannot compile on solidity 0.8, this project is on solidity 0.7.x.

The OpenZeppelin dependency reflects this as well (https://github.com/OpenZeppelin/openzeppelin-contracts/tree/release-v3.4-solc-0.7)

# testing

run `forge test -vvv`

# Deployment

Test the deployment script by running `forge 
cp .env.sample .env
Fill in your privary key, and run:
forge script script/uniswapv3lp.s.sol:UniswapV3lpScript --rpc-url $RPC_URL --broadcast --verify -vvvv
