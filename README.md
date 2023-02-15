# gnd

Did not use https://github.com/Uniswap/v3-core as it doesn't compile on solidity v0.8, instead used forks https://github.com/solidity-external-tests/uniswap-v3-core/tree/main_080 (from a uniswap team member) and the periphery is from a PR https://github.com/Uniswap/v3-periphery/pull/271

Installed by doing:
```
forge install solidity-external-tests/uniswap-v3-core@main_080
forge install ChrisiPK/v3-periphery@patch-1
```