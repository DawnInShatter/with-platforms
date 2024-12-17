// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IFaucet {
    /**
     * @notice Function to mint Testnet USDT tokens to the destination address
     * @param token The address of the token to perform the mint
     * @param to The address to send the minted tokens
     * @param amount The amount of tokens to mint
     * @return The amount minted
     **/
    function mint(
        address token,
        address to,
        uint256 amount
    ) external returns (uint256);

    function claimOJEE(
        address token_,
        address to_,
        uint256 amount_,
        uint256 expire_,
        bytes calldata signature_
    ) external;

    event EventClaimToken(
        address token,
        address to,
        uint256 amount,
        bytes signature
    );
}
