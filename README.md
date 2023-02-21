# gnd

Since https://github.com/Uniswap/v3-core and v3-periphery cannot compile on solidity 0.8, this project is on solidity 0.7.x.

The OpenZeppelin dependency reflects this as well (https://github.com/OpenZeppelin/openzeppelin-contracts/tree/release-v3.4-solc-0.7)

# testing

run `forge test -vvv`

# Deployment

To test the development script under script/ dir, run:

```
forge script script/uniswapv3lp.s.sol:UniswapV3lpScript  --rpc-url https://goerli-rollup.arbitrum.io/rpc
```

To publish to prod, run:

```
cp .env.sample .env
```

Fill in your privary key to .env file, and run:
```
forge script script/uniswapv3lp.s.sol:UniswapV3lpScript  --rpc-url https://arb1.arbitrum.io/rpc --broadcast --verify -vvvv
```

