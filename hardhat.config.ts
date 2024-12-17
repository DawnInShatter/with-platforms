import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import { UpgrateableContractsList } from "./helper-hardhat-config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-storage-layout-changes";
import "hardhat-abi-exporter";
import "@nomiclabs/hardhat-solhint";

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.19",
        settings: {
            evmVersion: "london",
            optimizer: {
                runs: 200,
                enabled: true,
            },
            outputSelection: {
                "*": {
                    "*": ["storageLayout"],
                },
            },
        },
    },
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545",
        },
        eth_mainnet: {
            url: process.env.MAINNET_RPC_URL || "",
            accounts:
                process.env.ETH_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        eth_sapphire: {
            url: process.env.MAINNET_RPC_URL || "",
            accounts:
                process.env.ETH_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        eth_sepolia_alpha: {
            url: process.env.ETH_SEPOLIA_RPC_URL || "",
            accounts:
                process.env.ETH_ALPHA_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_ALPHA_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        eth_sepolia_testnet: {
            url: process.env.ETH_SEPOLIA_RPC_URL || "",
            accounts:
                process.env.ETH_TEST_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_TEST_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        eth_sepolia_next: {
            url: process.env.ETH_SEPOLIA_RPC_URL || "",
            accounts:
                process.env.ETH_NEXT_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_NEXT_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        base_mainnet: {
            url: process.env.BASE_MAINNET_RPC_URL || "",
            accounts:
                process.env.ETH_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        base_sepolia_testnet: {
            url: process.env.BASE_SEPOLIA_RPC_URL || "",
            accounts:
                process.env.ETH_TEST_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_TEST_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
        base_sepolia_next: {
            url: process.env.BASE_SEPOLIA_RPC_URL || "",
            accounts:
                process.env.ETH_NEXT_PRIVATE_KEY !== undefined
                    ? [process.env.ETH_NEXT_PRIVATE_KEY]
                    : [],
            allowUnlimitedContractSize: true,
        },
    },
    etherscan: {
        // apiKey: process.env.ETHERSCAN_API_KEY,
        apiKey: {
            base_sepolia_next: process.env.ETHERSCAN_API_KEY,
        },
        customChains: [
            {
                network: "base_sepolia_next",
                chainId: 84532,
                urls: {
                    apiURL: "https://api-sepolia.basescan.org/api",
                    browserURL: "https://sepolia.basescan.org/",
                },
            },
        ],
    },
    paths: {
        sources: "./contracts",
        tests: "test",
        storageLayouts: ".storage-layouts",
    },
    gasReporter: {
        enabled: false,
    },
    mocha: {
        timeout: 3600000,
    },
    storageLayoutChanges: {
        contracts: UpgrateableContractsList,
        fullPath: false,
    },
    abiExporter: {
        path: "./contract_abi",
        runOnCompile: true,
        except: ["/interfaces/+", "/test/(?!(USDT|USDC|WETH|IFaucet))+"],
        clear: true,
        flat: true,
    },
};

export default config;
