import { artifacts, ethers, network } from "hardhat";
import fs from "fs";
import { UpgrateableContractsList } from "../helper-hardhat-config";
import {
    Contract,
    ContractFactory,
    ContractTransaction,
    Overrides,
    Signer,
    utils,
} from "ethers";
import { PromiseOrValue } from "../typechain-types/common";
import { XCProxyAdmin } from "../typechain-types";
import { Provider, TransactionRequest } from "@ethersproject/providers";
import assert from "assert";

export const DEFAULT_ADMIN_ROLE = ethers.constants.HashZero;
export const ADMIN_ROLE = ethers.utils.id("ADMIN_ROLE");
export const ZeroAddress = ethers.constants.AddressZero;

export const runEnvironment = () => {
    return network.name
        .replace("eth_", "")
        .replace("base_", "")
        .replace("hardhat", "localhost");
};

export const getAssert = (condition?: boolean, message?: string) => {
    if (condition) {
        return 0;
    }
    console.log("\x1b[91m", "Assertion failed: " + message, "\x1b[0m");
    return 1;
};

export const deployContract = async (contractName: any, ...params: any[]) => {
    let _Contract: any = await ethers.getContractFactory(contractName);
    let ct_contract = await _Contract.deploy(...params);
    console.log(
        `deploying => \"${contractName}\" -hash: \"${ct_contract.deployTransaction.hash}\" -nonce: \"${ct_contract.deployTransaction.nonce}\",`,
    );
    await ct_contract.deployed();

    console.log(`deployed => \"${contractName}\": \"${ct_contract.address}\",`);
    return ct_contract;
};

export const linkContract = async (
    contractName: any,
    contractAddress: any,
    contractKey?: any,
) => {
    let ct_contract: any = await ethers.getContractAt(
        contractName,
        contractAddress,
    );
    if (contractKey === undefined) {
        contractKey = contractName;
    }
    console.log(`linked => \"${contractKey}:\" \"${ct_contract.address}\"`);
    return ct_contract;
};

export const writeLog = (text: string, op_ret: any) => {
    console.log(`\"${text}\" -txhash:`, op_ret.hash);
};

export const writeContractsToJsonFile = async (
    contractObjDict: any,
    fileName: any,
) => {
    let jsonData: any = { deployed: {}, linked: {}, upgradeable: {} };
    jsonData["updateTime"] = new Date();
    for (let _contractName in contractObjDict) {
        let contractObj = contractObjDict[_contractName];
        let artifact = await artifacts.readArtifact(_contractName);
        let _blockNumber = "0";
        let operate = "deployed";
        if (contractObj.deployTransaction) {
            _blockNumber = (
                await contractObj.deployTransaction.wait()
            ).blockNumber.toString();
        } else {
            operate = "linked";
        }
        let abiName = artifact.contractName;
        if (abiName === "OJEEFaucet") {
            abiName = "IFaucet";
        }
        if (contractObj.proxy) {
            jsonData[operate][_contractName] = {
                address: contractObj.address,
                block: _blockNumber,
                proxy: contractObj.proxy,
                implementation: contractObj.implementation,
                proxyAdmin: contractObj.proxyAdmin,
                meta: {
                    contract: abiName,
                    path: "contract_abi/" + abiName + ".json",
                },
                legacyAddresses: [],
            };
        } else {
            jsonData[operate][_contractName] = {
                address: contractObj.address,
                block: _blockNumber,
                meta: {
                    contract: abiName,
                    path: "contract_abi/" + abiName + ".json",
                },
                legacyAddresses: [],
            };
        }
    }

    console.log("write to:", fileName);
    fs.writeFileSync(fileName, JSON.stringify(jsonData, null, 4));
};

export const waitForTx = async (text: any, tx: ContractTransaction) => {
    console.log(`\"Pending-${text}\" -txhash:"`, tx.hash);
    await tx.wait(1);
    console.log(`\"${text}\" -txhash:`, tx.hash);
};

export const sleep = async (time: any) => {
    return new Promise((resolve) => setTimeout(resolve, time * 1000));
};

export class XCProxyAdminManager {
    _xcProxyAdmin: XCProxyAdmin;

    constructor(xcProxyAdminObj: XCProxyAdmin) {
        this._xcProxyAdmin = xcProxyAdminObj;
    }

    async linkProxy(
        contractName: string,
        proxyAddress: string,
    ): Promise<Contract> {
        let oldImplementationAddress =
            await this._xcProxyAdmin.getProxyImplementation(proxyAddress);

        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            proxyAddress,
        );
        ct_Contract.proxy = proxyAddress;
        ct_Contract.implementation = oldImplementationAddress;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;

        console.log(
            `linked => \"${contractName}:\" \"${ct_Contract.address}\"`,
        );

        return ct_Contract;
    }

    async deployProxy(
        contractName: string,
        args?: unknown[],
    ): Promise<Contract> {
        console.log("==========>");
        if (!UpgrateableContractsList.includes(contractName)) {
            throw new Error(
                `Contract - \"${contractName}\" is not  upgrateable contract`,
            );
        }
        let _impl_Contract: any = await ethers.getContractFactory(contractName);
        let ct_impl = await _impl_Contract.deploy();
        console.log(
            `deploying hash => \"${ct_impl.deployTransaction.hash}\" -nonce: \"${ct_impl.deployTransaction.nonce}\",`,
        );
        await ct_impl.deployed();
        console.log(
            `deploying => \"${contractName}\" -impl: \"${ct_impl.address}\",`,
        );
        let initEncodedData;
        if (args === undefined) {
            initEncodedData = "0x";
        } else {
            initEncodedData = ct_impl.interface.encodeFunctionData(
                "initialize",
                args,
            );
        }
        // XCUpgradeableProxy
        const _proxy_Contract =
            await ethers.getContractFactory("XCUpgradeableProxy");
        const ct_XCUpgradeableProxy = await _proxy_Contract.deploy(
            ct_impl.address,
            this._xcProxyAdmin.address,
            initEncodedData,
        );
        await ct_XCUpgradeableProxy.deployed();
        console.log(
            `deployed over => \"${contractName}\" : \"${ct_XCUpgradeableProxy.address}\", -impl: \"${ct_impl.address}\"`,
        );

        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            ct_XCUpgradeableProxy.address,
        );
        ct_Contract.proxy = ct_XCUpgradeableProxy.address;
        ct_Contract.implementation = ct_impl.address;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;
        ct_Contract.deployTransaction = ct_XCUpgradeableProxy.deployTransaction;

        return ct_Contract;
    }

    async deployProxyWithDeployedContracts(
        contractName: string,
        proxyAddress: string,
        implementationAddress: string,
    ): Promise<Contract> {
        console.log("==========>");
        if (!UpgrateableContractsList.includes(contractName)) {
            throw new Error(
                `Contract - \"${contractName}\" is not  upgrateable contract`,
            );
        }
        await writeLog(
            "proxyAdmin.upgrade",
            await this._xcProxyAdmin.upgrade(
                proxyAddress,
                implementationAddress,
            ),
        );
        console.log(
            `deployed over => \"${contractName}\" : \"${proxyAddress}\",`,
        );

        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            proxyAddress,
        );
        ct_Contract.proxy = proxyAddress;
        ct_Contract.implementation = implementationAddress;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;

        return ct_Contract;
    }

    async deployProxyWithDeployedImpl(
        contractName: string,
        implementationAddress: string,
        args?: unknown[],
    ): Promise<Contract> {
        console.log("==========>");
        if (!UpgrateableContractsList.includes(contractName)) {
            throw new Error(
                `Contract - \"${contractName}\" is not  upgrateable contract`,
            );
        }
        let ct_impl: any = await ethers.getContractAt(
            contractName,
            implementationAddress,
        );
        let initEncodedData;
        if (args === undefined) {
            initEncodedData = "0x";
        } else {
            initEncodedData = ct_impl.interface.encodeFunctionData(
                "initialize",
                args,
            );
        }
        // XCUpgradeableProxy
        const _proxy_Contract =
            await ethers.getContractFactory("XCUpgradeableProxy");
        const ct_XCUpgradeableProxy = await _proxy_Contract.deploy(
            ct_impl.address,
            this._xcProxyAdmin.address,
            initEncodedData,
        );
        console.log(
            `deploying hash => \"${ct_XCUpgradeableProxy.deployTransaction.hash}\" -nonce: \"${ct_XCUpgradeableProxy.deployTransaction.nonce}\",`,
        );
        await ct_XCUpgradeableProxy.deployed();
        console.log(
            `deployed over => \"${contractName}\" : \"${ct_XCUpgradeableProxy.address}\", -impl: \"${ct_impl.address}\"`,
        );

        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            ct_XCUpgradeableProxy.address,
        );
        ct_Contract.proxy = ct_XCUpgradeableProxy.address;
        ct_Contract.implementation = ct_impl.address;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;
        ct_Contract.deployTransaction = ct_XCUpgradeableProxy.deployTransaction;

        return ct_Contract;
    }

    async upgradeProxy(
        proxyAddress: string,
        contractName: string,
    ): Promise<Contract> {
        console.log("==========>");
        if (!UpgrateableContractsList.includes(contractName)) {
            throw new Error(
                `Contract - \"${contractName}\" is not  upgrateable contract`,
            );
        }
        let _impl_Contract: any = await ethers.getContractFactory(contractName);
        let ct_impl = await _impl_Contract.deploy();
        await ct_impl.deployed();
        console.log(
            `deploying => \"${contractName}\" -impl: \"${ct_impl.address}\",`,
        );

        await writeLog(
            "proxyAdmin.upgrade",
            await this._xcProxyAdmin.upgrade(proxyAddress, ct_impl.address),
        );

        console.log(
            `upgraded over => \"${contractName}\" : \"${proxyAddress}\", -impl: \"${ct_impl.address}\"`,
        );

        let oldImplementationAddress =
            await this._xcProxyAdmin.getProxyImplementation(proxyAddress);
        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            proxyAddress,
        );
        ct_Contract.proxy = proxyAddress;
        ct_Contract.implementation = ct_impl.address;
        ct_Contract.oldImplementation = oldImplementationAddress;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;

        return ct_Contract;
    }

    async upgradeProxyWithDeployedImpl(
        proxyAddress: string,
        contractName: string,
        implementationAddress: string,
    ): Promise<Contract> {
        console.log("==========>");
        if (!UpgrateableContractsList.includes(contractName)) {
            throw new Error(
                `Contract - \"${contractName}\" is not  upgrateable contract`,
            );
        }
        let oldImplementationAddress =
            await this._xcProxyAdmin.getProxyImplementation(proxyAddress);

        await writeLog(
            "proxyAdmin.upgrade",
            await this._xcProxyAdmin.upgrade(
                proxyAddress,
                implementationAddress,
            ),
        );

        let ct_Contract: any = await ethers.getContractAt(
            contractName,
            proxyAddress,
        );
        ct_Contract.proxy = proxyAddress;
        ct_Contract.implementation = implementationAddress;
        ct_Contract.oldImplementation = oldImplementationAddress;
        ct_Contract.proxyAdmin = this._xcProxyAdmin.address;

        return ct_Contract;
    }
}

export class Manager {
    CONFIG: any;
    RunENV: any;
    filename: string;
    contractObjDict: any = {};
    proxyAdminManagerDict: any = {};

    constructor(staticConfig: any, curConfig: any, runENV: any, filename: any) {
        if (curConfig === undefined) {
            curConfig = {};
        }
        this.CONFIG = { ...staticConfig[runENV], ...curConfig };
        this.RunENV = runENV;
        this.filename = filename;
    }

    increaseConfig(incConfig: any) {
        this.CONFIG = { ...this.CONFIG, ...incConfig };
        return this.CONFIG;
    }

    async addProxyAdmin(adminAddress: string): Promise<XCProxyAdminManager> {
        if (!this.proxyAdminManagerDict[adminAddress]) {
            let adminObj = await linkContract("XCProxyAdmin", adminAddress);
            this.proxyAdminManagerDict[adminAddress] = new XCProxyAdminManager(
                adminObj,
            );
        }

        return this.proxyAdminManagerDict[adminAddress];
    }

    async deployUpgradeableOrLink(
        contractName: string,
        proxyAdminAddress: string,
        params?: any[],
    ) {
        let ct_contract;
        let proxyAdminManagerObj = await this.addProxyAdmin(proxyAdminAddress);
        if (
            this.CONFIG["deployedContract"] &&
            this.CONFIG.deployedContract[contractName]
        ) {
            ct_contract = await proxyAdminManagerObj.linkProxy(
                contractName,
                this.CONFIG.deployedContract[contractName],
            );
        } else if (
            this.CONFIG["deployedUpgradeableContract"] &&
            this.CONFIG.deployedUpgradeableContract[contractName]
        ) {
            ct_contract =
                await proxyAdminManagerObj.deployProxyWithDeployedContracts(
                    contractName,
                    this.CONFIG.deployedUpgradeableContract[contractName].proxy,
                    this.CONFIG.deployedUpgradeableContract[contractName]
                        .implementation,
                );
        } else {
            ct_contract = await proxyAdminManagerObj.deployProxy(
                contractName,
                params,
            );
        }

        this.contractObjDict[contractName] = ct_contract;
        await this.writeToJsonFile();
        return ct_contract;
    }

    async deployUpgradeableWithDeployedImplOrLink(
        contractName: string,
        proxyAdminAddress: string,
        implementationAddress: string,
        params?: any[],
    ) {
        let ct_contract;
        let proxyAdminManagerObj = await this.addProxyAdmin(proxyAdminAddress);
        if (
            this.CONFIG["deployedContract"] &&
            this.CONFIG.deployedContract[contractName]
        ) {
            ct_contract = await proxyAdminManagerObj.linkProxy(
                contractName,
                this.CONFIG.deployedContract[contractName],
            );
        } else if (
            this.CONFIG["deployedUpgradeableContract"] &&
            this.CONFIG.deployedUpgradeableContract[contractName]
        ) {
            ct_contract =
                await proxyAdminManagerObj.deployProxyWithDeployedContracts(
                    contractName,
                    this.CONFIG.deployedUpgradeableContract[contractName].proxy,
                    this.CONFIG.deployedUpgradeableContract[contractName]
                        .implementation,
                );
        } else {
            ct_contract =
                await proxyAdminManagerObj.deployProxyWithDeployedImpl(
                    contractName,
                    implementationAddress,
                    params,
                );
        }

        this.contractObjDict[contractName] = ct_contract;
        await this.writeToJsonFile();
        return ct_contract;
    }

    async upgradeUpgradeableOrLink(
        contractName: string,
        proxyAdminAddress: string,
        proxyAddress: string,
    ) {
        let ct_contract;
        let proxyAdminManagerObj = await this.addProxyAdmin(proxyAdminAddress);
        if (
            this.CONFIG["deployedContract"] &&
            this.CONFIG.deployedContract[contractName]
        ) {
            ct_contract = await proxyAdminManagerObj.linkProxy(
                contractName,
                this.CONFIG.deployedContract[contractName],
            );
        } else {
            ct_contract = await proxyAdminManagerObj.upgradeProxy(
                proxyAddress,
                contractName,
            );
        }

        this.contractObjDict[contractName] = ct_contract;
        await this.writeToJsonFile();
        return ct_contract;
    }

    async upgradeUpgradeableWithDeployedImplOrLink(
        contractName: string,
        proxyAdminAddress: string,
        proxyAddress: string,
        implementationAddress: string,
    ) {
        let ct_contract;
        let proxyAdminManagerObj = await this.addProxyAdmin(proxyAdminAddress);
        ct_contract = await proxyAdminManagerObj.upgradeProxyWithDeployedImpl(
            proxyAddress,
            contractName,
            implementationAddress,
        );

        this.contractObjDict[contractName] = ct_contract;
        await this.writeToJsonFile();
        return ct_contract;
    }

    async deployOrLinkContract(contractName: any, ...params: any[]) {
        let ct_contract;
        if (
            this.CONFIG["deployedContract"] &&
            this.CONFIG.deployedContract[contractName]
        ) {
            ct_contract = await linkContract(
                contractName,
                this.CONFIG.deployedContract[contractName],
            );
        } else {
            ct_contract = await deployContract(contractName, ...params);
        }
        this.contractObjDict[contractName] = ct_contract;
        await this.writeToJsonFile();
        return ct_contract;
    }

    async transferOwnerShipWithNew(contractName: string, newOwner: string) {
        const ct_Contract = await linkContract(
            contractName,
            this.CONFIG.NewDeployedContract[contractName],
        );
        writeLog(
            `${contractName} transferOwnership to ${newOwner}`,
            await ct_Contract.transferOwnership(newOwner),
        );
    }

    async transferOwnerShip(
        contractName: string,
        contractAddress: string,
        newOwner: string,
    ) {
        const ct_Contract = await linkContract(contractName, contractAddress);
        writeLog(
            `${contractName} transferOwnership to ${newOwner}`,
            await ct_Contract.transferOwnership(newOwner),
        );
    }

    async setAdminWithNew(
        contractName: string,
        newSuperAdmin: string,
        ...adminWallets: any[]
    ) {
        const ct_Contract = await linkContract(
            contractName,
            this.CONFIG.NewDeployedContract[contractName],
        );
        writeLog(
            `${contractName} set super admin to ${newSuperAdmin}`,
            await ct_Contract.grantRole(DEFAULT_ADMIN_ROLE, newSuperAdmin),
        );
        for (let adminWallet of adminWallets) {
            writeLog(
                `${contractName} set admin to ${adminWallet}`,
                await ct_Contract.grantRole(ADMIN_ROLE, adminWallet),
            );
        }
    }

    async setAdmin(
        contractName: string,
        contractAddress: string,
        newSuperAdmin: string,
        ...adminWallets: any[]
    ) {
        const ct_Contract = await linkContract(contractName, contractAddress);
        writeLog(
            `${contractName}-${contractAddress} set super admin to ${newSuperAdmin}`,
            await ct_Contract.grantRole(DEFAULT_ADMIN_ROLE, newSuperAdmin),
        );
        for (let adminWallet of adminWallets) {
            writeLog(
                `${contractName}-${contractAddress} set admin to ${adminWallet}`,
                await ct_Contract.grantRole(ADMIN_ROLE, adminWallet),
            );
        }
    }

    async revokeSuperAdminFromSelfWithNew(
        contractName: string,
        newSuperAdmin: string,
    ) {
        const [owner] = await ethers.getSigners();
        let oldSuperAdmin = owner.address;
        const ct_Contract = await linkContract(
            contractName,
            this.CONFIG.NewDeployedContract[contractName],
        );
        assert(
            newSuperAdmin != oldSuperAdmin,
            `${contractName} Error! new super admin is same as old superadmin`,
        );
        assert(
            await ct_Contract.hasRole(DEFAULT_ADMIN_ROLE, newSuperAdmin),
            `${contractName} Error! account-${newSuperAdmin} is not super admin`,
        );

        writeLog(
            `${contractName} revoke super admin from ${oldSuperAdmin}`,
            await ct_Contract.revokeRole(DEFAULT_ADMIN_ROLE, oldSuperAdmin),
        );
    }

    async revokeSuperAdminFromSelf(
        contractName: string,
        contractAddress: string,
        newSuperAdmin: string,
    ) {
        const [owner] = await ethers.getSigners();
        let oldSuperAdmin = owner.address;
        const ct_Contract = await linkContract(contractName, contractAddress);
        assert(
            newSuperAdmin != oldSuperAdmin,
            `${contractName} Error! new super admin is same as old superadmin`,
        );
        assert(
            await ct_Contract.hasRole(DEFAULT_ADMIN_ROLE, newSuperAdmin),
            `${contractName} Error! account-${newSuperAdmin} is not super admin`,
        );

        writeLog(
            `${contractName} revoke super admin from ${oldSuperAdmin}`,
            await ct_Contract.revokeRole(DEFAULT_ADMIN_ROLE, oldSuperAdmin),
        );
    }

    async revokeAdmin(
        contractName: string,
        contractAddress: string,
        ...adminWallets: any[]
    ) {
        const ct_Contract = await linkContract(contractName, contractAddress);
        for (let adminWallet of adminWallets) {
            if (await ct_Contract.hasRole(ADMIN_ROLE, adminWallet)) {
                writeLog(
                    `${contractName} revoke admin from ${adminWallet}`,
                    await ct_Contract.revokeRole(ADMIN_ROLE, adminWallet),
                );
            }
        }
    }

    async checkPermission(
        linkContractName: string,
        contractAddress: string,
        ownerAddres: string,
        superAndAdminWallets: any[],
    ) {
        const ct_Contract = await linkContract(
            linkContractName,
            contractAddress,
        );
        let _assertNum = 0;
        let _owner = await ct_Contract.owner();
        _assertNum += getAssert(
            _owner === ownerAddres,
            `${linkContractName}'s owner(${_owner}) is not match, ${ownerAddres}`,
        );
        if (superAndAdminWallets.length > 0) {
            _assertNum += getAssert(
                await ct_Contract.hasRole(
                    DEFAULT_ADMIN_ROLE,
                    superAndAdminWallets[0],
                ),
                `${linkContractName}'s superAdmin is not match, ${superAndAdminWallets[0]}`,
            );
        }
        for (let i = 1; i < superAndAdminWallets.length; i++) {
            _assertNum += getAssert(
                await ct_Contract.hasRole(ADMIN_ROLE, superAndAdminWallets[i]),
                `${linkContractName}'s admin is not match, ${superAndAdminWallets[i]}`,
            );
        }
        return _assertNum;
    }

    async writeToJsonFile() {
        let fn =
            this.filename.replace(".ts", "") + `-${this.RunENV}-config.json`;
        await writeContractsToJsonFile(this.contractObjDict, fn);
    }
}
