import fs from "fs";
import { UpgrateableContractsList } from "../helper-hardhat-config";

let fPath = __dirname + "/../";
getUpgradeContracts(fPath);

function getUpgradeContracts(fPath: any) {
    let loseFile: any[] = [];
    let allUpgradeableContracts: any[] = [];
    const aPath = fPath + "contract_abi";
    if (!fs.existsSync(aPath)) {
        throw new Error(`指定的目录${aPath}不存在！`);
    }
    const sPath = fPath + ".storage-layouts";
    if (!fs.existsSync(sPath)) {
        throw new Error(`指定的目录${sPath}不存在！`);
    }
    const abiFiles = fs.readdirSync(aPath);
    for (let i = 0; i < abiFiles.length; i++) {
        let file = abiFiles[i]; // 文件名称（不包含文件路径）
        let currentFilePath = aPath + "/" + file;
        // @ts-ignore
        let data = JSON.parse(fs.readFileSync(currentFilePath));
        for (let abiData of data) {
            if (abiData.name === "initialize") {
                let fileName = file.replace(".json", "");
                if (-1 === UpgrateableContractsList.indexOf(fileName)) {
                    loseFile.push(fileName);
                }
            }
        }
    }
    if (loseFile.length > 0) {
        throw new Error("Please mark as upgradable contracts：\n" + loseFile);
    }
    const storageFiles = fs.readdirSync(sPath);
    for (let i = 0; i < storageFiles.length; i++) {
        let fileName = storageFiles[i].replace(".json", "");
        allUpgradeableContracts.push(fileName);
    }

    for (let upgradeableContract of UpgrateableContractsList) {
        if (-1 === allUpgradeableContracts.indexOf(upgradeableContract)) {
            throw new Error(
                "Please update storage for new upgradable contracts：" +
                    upgradeableContract,
            );
        }
    }
}
