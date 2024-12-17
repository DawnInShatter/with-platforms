import { network } from "hardhat";

const ETH_STATIC = {
    sepolia_next: {
        USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
        WETH: "0x2D5ee574e710219a521449679A4A7f2B43f046ad", // WETH9

        XCProxyAdmin: "0x2767818007B806092959C96B2705c6e8B5Acd7b4",

        Comet_WETH: "0x2943ac1216979aD8dB76D9147F64E61adc126e96",
        Comet_USDC: "0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e",
        CometReward: "0x8bF5b658bdF0388E8b482ED51B14aef58f90abfD",
        // BASE-UniswapV3Router: "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4",
        UniswapV3Router: "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E",
        UniswapNonfungiblePositionManager:
            "0x1238536071E1c677A632429e3655c799b22cDA52",

        AavePool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
        AToken_WETH: "0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830",

        Proxy: {},
        ReDeployedContract: {},
        NewDeployedContract: {
            WithUniswapV3: "0xCbA42b6aBEa3764eB9ECC23C45206fd3992f4969",
            WithCompoundV3: "0x315eA73BB85C7b4fD57cb64D0ee7cD43132C1Dab",
            WithAaveV3: "0x8a1ac546f1958780bEb8c84988FC6abFDe2D9195",

            Impl_WithUniswapV3: "0x7374ac720DfdDE0493aa8621205Af88464424D16",
            Impl_WithCompoundV3: "0x40dcB61471fC1e8b78697FC320355f7bdc2Ce4a1",
            Impl_WithAaveV3: "0x5B52c2c8b164AFbc7739E873515E44576382103D",
        },
    },
};
const BASE_STATIC = {
    sepolia_next: {
        // USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
        // WETH: "0x2D5ee574e710219a521449679A4A7f2B43f046ad", // WETH9

        XCProxyAdmin: "0x877be51b3B0446A58Ff1E302fF3333854945313b",

        // Comet_WETH: "0x2943ac1216979aD8dB76D9147F64E61adc126e96",
        // Comet_USDC: "0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e",
        // CometReward: "0x8bF5b658bdF0388E8b482ED51B14aef58f90abfD",
        UniswapV3Router: "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4",
        UniswapNonfungiblePositionManager:
            "0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2",

        // AavePool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
        // AToken_WETH: "0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830",

        Proxy: {},
        ReDeployedContract: {},
        NewDeployedContract: {
            WithUniswapV3: "0x89bf50Da2Da709478da60CE3ad8D279486566D2A",
            // WithCompoundV3: "0x315eA73BB85C7b4fD57cb64D0ee7cD43132C1Dab",
            // WithAaveV3: "0x8a1ac546f1958780bEb8c84988FC6abFDe2D9195",

            Impl_WithUniswapV3: "0xd049a4617333D7c6d14eBaB8514e5991e0FEaEc5",
            // Impl_WithCompoundV3: "0x40dcB61471fC1e8b78697FC320355f7bdc2Ce4a1",
            // Impl_WithAaveV3: "0x5B52c2c8b164AFbc7739E873515E44576382103D",
        },
    },
};

let networkName = network.name;
let staticData: any;
if (networkName.includes("base_")) {
    staticData = BASE_STATIC;
} else if (networkName.includes("eth_")) {
    staticData = ETH_STATIC;
} else {
    throw Error("Chain name error!");
}

export const STATIC = staticData;
