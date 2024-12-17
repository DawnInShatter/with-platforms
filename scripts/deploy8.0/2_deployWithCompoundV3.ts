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
    // WithCompoundV3
    const ct_WithCompoundV3 =
        await manager.deployUpgradeableWithDeployedImplOrLink(
            "WithCompoundV3",
            CONFIG.XCProxyAdmin,
            CONFIG.NewDeployedContract.Impl_WithCompoundV3,
            [CONFIG.USDC, CONFIG.Comet_USDC, CONFIG.CometReward],
        );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
