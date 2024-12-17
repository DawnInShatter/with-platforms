import { ethers } from "hardhat";
import {
    writeLog,
    runEnvironment,
    Manager,
    linkContract,
    getAssert,
} from "../utils";
import { STATIC } from "./AddressConfig";

const CUR_STATIC = {};
let manager = new Manager(STATIC, CUR_STATIC, runEnvironment(), __filename);
const CONFIG = manager.CONFIG;

async function main() {
    const owner = (await ethers.getSigners())[0];
    console.log("owner:", owner.address, " env:", manager.RunENV);

    console.log("Contract deploy =====>");
    // // WithUniswapV3
    // const ct_WithUniswapV3 =
    //     await manager.deployUpgradeableWithDeployedImplOrLink(
    //         "WithUniswapV3",
    //         CONFIG.XCProxyAdmin,
    //         CONFIG.NewDeployedContract.Impl_WithUniswapV3,
    //         [
    //             CONFIG.UniswapV3Router
    //         ],
    //     );
    const ct_WithUniswapV3 =
        await manager.upgradeUpgradeableWithDeployedImplOrLink(
            "WithUniswapV3",
            CONFIG.XCProxyAdmin,
            CONFIG.NewDeployedContract.WithUniswapV3,
            CONFIG.NewDeployedContract.Impl_WithUniswapV3,
        );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
