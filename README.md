# With platforms

## Version of npm must be 7 or later

```
npm -v
```

## Install package

```
npm install
```

## Typechain Helpers

```
npx hardhat compile
```

## Run Test

```
npx hardhat test
```

## Deploy

```
npx hardhat run scripts/deploy_proxy.ts --network [eth_sapphire, eth_sepolia_alpha_testnet_next]
```

## Verify : by contract address, one contract once

```
npx hardhat verify --network [eth_sapphire, eth_sepolia_alpha_testnet_next] xxx
```

## Export abi : export abi files to ./abi

```
npm run export-abi
```

## Storage layout change abount upgradable contracts
### check. If slots changes, it will error. If found new storage, it will not error.
```
npm run check-storage
```
### update. Reset the storage layout json file after check.
```
npm run update-storage
```
### force update. Reset the storage layout json file without check.
```
npm run force:update-storage
```

## Format solidity code and typescript code
```
npm run format
```
## Check that you have formatted the codes
```
npm run check-format
```
### Verify the security and style guide of the code, and check that the code has been formatted
, Rules: https://github.com/protofire/solhint/blob/develop/docs/rules.md
```
npm run check
```
