import {
    ADMIN_ROLE,
    linkContract,
    Manager,
    runEnvironment,
    sleep,
    writeLog,
} from "../utils";
import { ethers } from "hardhat";
import { STATIC } from "./AddressConfig";

const CUR_STATIC = {};
let manager = new Manager(STATIC, CUR_STATIC, runEnvironment(), __filename);
const CONFIG = manager.CONFIG;

async function main() {
    const [owner] = await ethers.getSigners();
    console.log("owner:", owner.address, " env:", manager.RunENV);

    console.log("========== Contracts deploy ==========");

    // // XCProxyAdmin
    // const ct_XCProxyAdmin = await manager.deployOrLinkContract(
    //     "XCProxyAdmin",
    // );
    // await sleep(3);

    // WithUniswapV3 Implementation
    console.log(CONFIG.UniswapNonfungiblePositionManager);
    const ct_WithUniswapV3Impl = await manager.deployOrLinkContract(
        "WithUniswapV3",
        CONFIG.UniswapNonfungiblePositionManager,
    );
    await sleep(3);

    // // WithCompoundV3 Implementation
    // const ct_WithCompoundV3Impl = await manager.deployOrLinkContract("WithCompoundV3");
    // await sleep(3);

    // // WithAaveV3 Implementation
    // const ct_WithAaveV3Impl = await manager.deployOrLinkContract(
    //     "WithAaveV3",
    //     CONFIG.AavePool,
    //     CONFIG.AToken_WETH,
    //     CONFIG.UniswapV3Router
    // );
    // await sleep(3);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
