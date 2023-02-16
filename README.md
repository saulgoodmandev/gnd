# gnd

Did not use https://github.com/Uniswap/v3-core as it doesn't compile on solidity v0.8, instead used forks https://github.com/solidity-external-tests/uniswap-v3-core/tree/main_080 (from a uniswap team member) and the periphery is from a PR https://github.com/Uniswap/v3-periphery/pull/271

Installed by doing:
```
forge install solidity-external-tests/uniswap-v3-core@main_080
forge install ChrisiPK/v3-periphery@patch-1
```

If we want to go downgrade to an old version of solidity, then use https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v3.4.2-solc-0.7.  We can then remove the `libraries/` folder, copied directly from unipilot-v2
