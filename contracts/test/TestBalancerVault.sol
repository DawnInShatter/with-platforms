// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
pragma solidity ^0.8.0;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AdminHelperUpgradeable} from "../helpers/AdminHelperUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IWETH} from "../interfaces/IWETH.sol";

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

/**
 * @dev Full external interface for the Vault core contract - no external or public methods exist in the contract that
 * don't one of these declarations.
 */
contract TestBalancerVault is
    ReentrancyGuardUpgradeable,
    AdminHelperUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    address private constant _ETH = address(0);

    IWETH public weth;

    /// @notice poolId => {token address => base amount}
    //    mapping(bytes32 => mapping(address => uint256)) public tokenBaseAmount;
    mapping(bytes32 => mapping(address => uint256)) public poolBalances;

    /**
     * @dev Data for a single swap executed by `swap`. `amount` is either `amountIn` or `amountOut` depending on
     * the `kind` value.
     *
     * `assetIn` and `assetOut` are either token addresses, or the IAsset sentinel value for ETH (the zero address).
     * Note that Pools never interact with ETH directly: it will be wrapped to or unwrapped from WETH by the Vault.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    struct SwapRequest {
        SwapKind kind;
        IERC20Upgradeable tokenIn;
        IERC20Upgradeable tokenOut;
        uint256 amount;
        // Misc data
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }

    /**
     * @dev Data for each individual swap executed by `batchSwap`. The asset in and out fields are indexes into the
     * `assets` array passed to that function, and ETH assets are converted to WETH.
     *
     * If `amount` is zero, the multihop mechanism is used to determine the actual amount based on the amount in/out
     * from the previous swap, depending on the swap kind.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    /**
     * @dev All tokens in a swap are either sent from the `sender` account to the Vault, or from the Vault to the
     * `recipient` account.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * If `fromInternalBalance` is true, the `sender`'s Internal Balance will be preferred, performing an ERC20
     * transfer for the difference between the requested amount and the User's Internal Balance (if any). The `sender`
     * must have allowed the Vault to use their tokens via `IERC20Upgradeable.approve()`. This matches the behavior of
     * `joinPool`.
     *
     * If `toInternalBalance` is true, tokens will be deposited to `recipient`'s internal balance instead of
     * transferred. This matches the behavior of `exitPool`.
     *
     * Note that ETH cannot be deposited to or withdrawn from Internal Balance: attempting to do so will trigger a
     * revert.
     */
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    /**
     * @dev Emitted for each individual swap performed by `swap` or `batchSwap`.
     */
    event Swap(
        bytes32 indexed poolId,
        IERC20Upgradeable indexed tokenIn,
        IERC20Upgradeable indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    modifier authenticateFor(address user) {
        _authenticateFor(user);
        _;
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __AdminHelper_init();
    }

    function addPool(
        bytes32 poolId_,
        address token0_,
        address token1_,
        uint256 baseAmount0_,
        uint256 baseAmount1_
    ) external onlyAdmin {
        poolBalances[poolId_][token0_] = baseAmount0_;
        poolBalances[poolId_][token1_] = baseAmount1_;
    }

    function changePool(
        bytes32 poolId_,
        address token0_,
        address token1_,
        uint256 baseAmount0_,
        uint256 baseAmount1_
    ) external onlyAdmin {
        poolBalances[poolId_][token0_] = baseAmount0_;
        poolBalances[poolId_][token1_] = baseAmount1_;
    }

    function setWETH(address weth_) external onlyAdmin {
        weth = IWETH(weth_);
    }

    /**
     * @dev Performs a swap with a single Pool.
     *
     * If the swap is 'given in' (the number of tokens to send to the Pool is known), it returns the amount of tokens
     * taken from the Pool, which must be greater than or equal to `limit`.
     *
     * If the swap is 'given out' (the number of tokens to take from the Pool is known), it returns the amount of tokens
     * sent to the Pool, which must be less than or equal to `limit`.
     *
     * Internal Balance usage and the recipient are determined by the `funds` struct.
     *
     * Emits a `Swap` event.
     */
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        authenticateFor(funds.sender)
        returns (uint256 amountCalculated)
    {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "Swap deadline");

        // This revert reason is for consistency with `batchSwap`: an equivalent `swap` performed using that function
        // would result in this error.
        require(singleSwap.amount > 0, "Unknown amount in first swap");

        IERC20Upgradeable tokenIn = IERC20Upgradeable(
            address(singleSwap.assetIn)
        );
        IERC20Upgradeable tokenOut = IERC20Upgradeable(
            address(singleSwap.assetOut)
        );
        require(tokenIn != tokenOut, "Cannot swap same token");

        // Initializing each struct field one-by-one uses less gas than setting all at once.
        SwapRequest memory poolRequest;
        poolRequest.poolId = singleSwap.poolId;
        poolRequest.kind = singleSwap.kind;
        poolRequest.tokenIn = tokenIn;
        poolRequest.tokenOut = tokenOut;
        poolRequest.amount = singleSwap.amount;
        poolRequest.userData = singleSwap.userData;
        poolRequest.from = funds.sender;
        poolRequest.to = funds.recipient;
        // The lastChangeBlock field is left uninitialized.

        uint256 amountIn;
        uint256 amountOut;

        (amountCalculated, amountIn, amountOut) = _swapWithPool(poolRequest);
        require(
            singleSwap.kind == SwapKind.GIVEN_IN
                ? amountOut >= limit
                : amountIn <= limit,
            "Swap limit"
        );

        _receiveAsset(
            singleSwap.assetIn,
            amountIn,
            funds.sender,
            funds.fromInternalBalance
        );
        _sendAsset(
            singleSwap.assetOut,
            amountOut,
            funds.recipient,
            funds.toInternalBalance
        );

        // If the asset in is ETH, then `amountIn` ETH was wrapped into WETH.
        _handleRemainingEth(_isETH(singleSwap.assetIn) ? amountIn : 0);
    }

    /**
     * @dev Performs a series of swaps with one or multiple Pools. In each individual swap, the caller determines either
     * the amount of tokens sent to or received from the Pool, depending on the `kind` value.
     *
     * Returns an array with the net Vault asset balance deltas. Positive amounts represent tokens (or ETH) sent to the
     * Vault, and negative amounts represent tokens (or ETH) sent by the Vault. Each delta corresponds to the asset at
     * the same index in the `assets` array.
     *
     * Swaps are executed sequentially, in the order specified by the `swaps` array. Each array element describes a
     * Pool, the token to be sent to this Pool, the token to receive from it, and an amount that is either `amountIn` or
     * `amountOut` depending on the swap kind.
     *
     * Multihop swaps can be executed by passing an `amount` value of zero for a swap. This will cause the amount in/out
     * of the previous swap to be used as the amount in for the current one. In a 'given in' swap, 'tokenIn' must equal
     * the previous swap's `tokenOut`. For a 'given out' swap, `tokenOut` must equal the previous swap's `tokenIn`.
     *
     * The `assets` array contains the addresses of all assets involved in the swaps. These are either token addresses,
     * or the IAsset sentinel value for ETH (the zero address). Each entry in the `swaps` array specifies tokens in and
     * out by referencing an index in `assets`. Note that Pools never interact with ETH directly: it will be wrapped to
     * or unwrapped from WETH by the Vault.
     *
     * Internal Balance usage, sender, and recipient are determined by the `funds` struct. The `limits` array specifies
     * the minimum or maximum amount of each token the vault is allowed to transfer.
     *
     * `batchSwap` can be used to make a single swap, like `swap` does, but doing so requires more gas than the
     * equivalent `swap` call.
     *
     * Emits `Swap` events.
     */
    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        authenticateFor(funds.sender)
        returns (int256[] memory assetDeltas)
    {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "Swap deadline");

        require(assets.length == limits.length, "Input length mismatch");

        // Perform the swaps, updating the Pool token balances and computing the net Vault asset deltas.
        assetDeltas = _swapWithPools(swaps, assets, funds, kind);

        // Process asset deltas, by either transferring assets from the sender (for positive deltas) or to the recipient
        // (for negative deltas).
        uint256 wrappedEth = 0;
        for (uint256 i = 0; i < assets.length; ++i) {
            IAsset asset = assets[i];
            int256 delta = assetDeltas[i];
            require(delta <= limits[i], "Swap limit");

            if (delta > 0) {
                uint256 toReceive = uint256(delta);
                _receiveAsset(
                    asset,
                    toReceive,
                    funds.sender,
                    funds.fromInternalBalance
                );

                if (_isETH(asset)) {
                    wrappedEth = wrappedEth + toReceive;
                }
            } else if (delta < 0) {
                uint256 toSend = uint256(-delta);
                _sendAsset(
                    asset,
                    toSend,
                    funds.recipient,
                    funds.toInternalBalance
                );
            }
        }

        // Handle any used and remaining ETH.
        _handleRemainingEth(wrappedEth);
    }

    /**
     * @dev Simulates a call to `batchSwap`, returning an array of Vault asset deltas. Calls to `swap` cannot be
     * simulated directly, but an equivalent `batchSwap` call can and will yield the exact same result.
     *
     * Each element in the array corresponds to the asset at the same index, and indicates the number of tokens (or ETH)
     * the Vault would take from the sender (if positive) or send to the recipient (if negative). The arguments it
     * receives are the same that an equivalent `batchSwap` call would receive.
     *
     * Unlike `batchSwap`, this function performs no checks on the sender or recipient field in the `funds` struct.
     * This makes it suitable to be called by off-chain applications via eth_call without needing to hold tokens,
     * approve them for the Vault, or even know a user's address.
     *
     * Note that this function is not 'view' (due to implementation details): the client code must explicitly execute
     * eth_call instead of eth_sendTransaction.
     * This function is not marked as `nonReentrant` because the underlying mechanism relies on reentrancy
     */
    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory) {
        // In order to accurately 'simulate' swaps, this function actually does perform the swaps, including calling the
        // Pool hooks and updating balances in storage. However, once it computes the final Vault Deltas, it
        // reverts unconditionally, returning this array as the revert data.
        //
        // By wrapping this reverting call, we can decode the deltas 'returned' and return them as a normal Solidity
        // function would. The only caveat is the function becomes non-view, but off-chain clients can still call it
        // via eth_call to get the expected result.
        //
        // This technique was inspired by the work from the Gnosis team in the Gnosis Safe contract:
        // https://github.com/gnosis/safe-contracts/blob/v1.2.0/contracts/GnosisSafe.sol#L265
        //
        // Most of this function is implemented using inline assembly, as the actual work it needs to do is not
        // significant, and Solidity is not particularly well-suited to generate this behavior, resulting in a large
        // amount of generated bytecode.

        if (msg.sender != address(this)) {
            // We perform an external call to ourselves, forwarding the same calldata. In this call, the else clause of
            // the preceding if statement will be executed instead.

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(this).call(msg.data);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // This call should always revert to decode the actual asset deltas from the revert reason
                switch success
                case 0 {
                    // Note we are manually writing the memory slot 0. We can safely overwrite whatever is
                    // stored there as we take full control of the execution and then immediately return.

                    // We copy the first 4 bytes to check if it matches with the expected signature, otherwise
                    // there was another revert reason and we should forward it.
                    returndatacopy(0, 0, 0x04)
                    let error := and(
                        mload(0),
                        0xffffffff00000000000000000000000000000000000000000000000000000000
                    )

                    // If the first 4 bytes don't match with the expected signature, we forward the revert reason.
                    if eq(
                        eq(
                            error,
                            0xfa61cc1200000000000000000000000000000000000000000000000000000000
                        ),
                        0
                    ) {
                        returndatacopy(0, 0, returndatasize())
                        revert(0, returndatasize())
                    }

                    // The returndata contains the signature, followed by the raw memory representation of an array:
                    // length + data. We need to return an ABI-encoded representation of this array.
                    // An ABI-encoded array contains an additional field when compared to its raw memory
                    // representation: an offset to the location of the length. The offset itself is 32 bytes long,
                    // so the smallest value we  can use is 32 for the data to be located immediately after it.
                    mstore(0, 32)

                    // We now copy the raw memory array from returndata into memory. Since the offset takes up 32
                    // bytes, we start copying at address 0x20. We also get rid of the error signature, which takes
                    // the first four bytes of returndata.
                    let size := sub(returndatasize(), 0x04)
                    returndatacopy(0x20, 0x04, size)

                    // We finally return the ABI-encoded array, which has a total length equal to that of the array
                    // (returndata), plus the 32 bytes for the offset.
                    return(0, add(size, 32))
                }
                default {
                    // This call should always revert, but we fail nonetheless if that didn't happen
                    invalid()
                }
            }
        } else {
            int256[] memory deltas = _swapWithPools(swaps, assets, funds, kind);

            // solhint-disable-next-line no-inline-assembly
            assembly {
                // We will return a raw representation of the array in memory, which is composed of a 32 byte length,
                // followed by the 32 byte int256 values. Because revert expects a size in bytes, we multiply the array
                // length (stored at `deltas`) by 32.
                let size := mul(mload(deltas), 32)

                // We send one extra value for the error signature "QueryError(int256[])" which is 0xfa61cc12.
                // We store it in the previous slot to the `deltas` array. We know there will be at least one available
                // slot due to how the memory scratch space works.
                // We can safely overwrite whatever is stored in this slot as we will revert immediately after that.
                mstore(
                    sub(deltas, 0x20),
                    0x00000000000000000000000000000000000000000000000000000000fa61cc12
                )
                let start := sub(deltas, 0x04)

                // When copying from `deltas` into returndata, we copy an additional 36 bytes to also return the array's
                // length and the error signature.
                revert(start, add(size, 36))
            }
        }
    }

    function getTokenBalance(
        bytes32 poolId_,
        address token_
    ) public view returns (uint256) {
        return poolBalances[poolId_][token_];
    }

    /**
     * @dev Receives `amount` of `asset` from `sender`. If `fromInternalBalance` is true, it first withdraws as much
     * as possible from Internal Balance, then transfers any remaining amount.
     *
     * If `asset` is ETH, `fromInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * will be wrapped into WETH.
     *
     * WARNING: this function does not check that the contract caller has actually supplied any ETH - it is up to the
     * caller of this function to check that this is true to prevent the Vault from using its own ETH (though the Vault
     * typically doesn't hold any).
     */
    function _receiveAsset(
        IAsset asset,
        uint256 amount,
        address sender,
        bool fromInternalBalance
    ) internal {
        if (amount == 0) {
            return;
        }

        if (_isETH(asset)) {
            require(!fromInternalBalance, "Invalid eth internal balance");

            // The ETH amount to receive is deposited into the WETH contract, which will in turn mint WETH for
            // the Vault at a 1:1 ratio.

            // A check for this condition is also introduced by the compiler, but this one provides a revert reason.
            // Note we're checking for the Vault's total balance, *not* ETH sent in this transaction.
            require(address(this).balance >= amount, "Insufficient eth");
            _WETH().deposit{value: amount}();
        } else {
            IERC20Upgradeable token = _asIERC20(asset);
            token.safeTransferFrom(sender, address(this), amount);
        }
    }

    /**
     * @dev Sends `amount` of `asset` to `recipient`. If `toInternalBalance` is true, the asset is deposited as Internal
     * Balance instead of being transferred.
     *
     * If `asset` is ETH, `toInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * are instead sent directly after unwrapping WETH.
     */
    function _sendAsset(
        IAsset asset,
        uint256 amount,
        address payable recipient,
        bool toInternalBalance
    ) internal {
        if (amount == 0) {
            return;
        }

        if (_isETH(asset)) {
            // Sending ETH is not as involved as receiving it: the only special behavior is it cannot be
            // deposited to Internal Balance.
            require(!toInternalBalance, "Invalid eth internal balance");

            // First, the Vault withdraws deposited ETH from the WETH contract, by burning the same amount of WETH
            // from the Vault. This receipt will be handled by the Vault's `receive`.
            _WETH().withdraw(amount);

            // Then, the withdrawn ETH is sent to the recipient.
            (bool success_, ) = recipient.call{value: amount}("");
            require(success_, "Fail to transfer native token");
        } else {
            IERC20Upgradeable token = _asIERC20(asset);
            token.safeTransfer(recipient, amount);
        }
    }

    /**
     * @dev Returns excess ETH back to the contract caller, assuming `amountUsed` has been spent. Reverts
     * if the caller sent less ETH than `amountUsed`.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender are
     * not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function _handleRemainingEth(uint256 amountUsed) internal {
        require(msg.value >= amountUsed, "Insufficient eth");

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            (bool success_, ) = msg.sender.call{value: excess}("");
            require(success_, "Fail to transfer native token");
        }
    }

    /**
     * @dev Given the two swap tokens and the swap kind, returns which one is the 'given' token (the token whose
     * amount is supplied by the caller).
     */
    function _tokenGiven(
        SwapKind kind,
        IERC20Upgradeable tokenIn,
        IERC20Upgradeable tokenOut
    ) private pure returns (IERC20Upgradeable) {
        return kind == SwapKind.GIVEN_IN ? tokenIn : tokenOut;
    }

    /**
     * @dev Given the two swap tokens and the swap kind, returns which one is the 'calculated' token (the token whose
     * amount is calculated by the Pool).
     */
    function _tokenCalculated(
        SwapKind kind,
        IERC20Upgradeable tokenIn,
        IERC20Upgradeable tokenOut
    ) private pure returns (IERC20Upgradeable) {
        return kind == SwapKind.GIVEN_IN ? tokenOut : tokenIn;
    }

    // This is not really an interface - it just defines common structs used by other interfaces: IGeneralPool and
    // IMinimalSwapInfoPool.
    //
    // This data structure represents a request for a token swap, where `kind` indicates the swap type ('given in' or
    // 'given out') which indicates whether or not the amount sent by the pool is known.
    //
    // The pool receives `tokenIn` and sends `tokenOut`. `amount` is the number of `tokenIn` tokens the pool will take
    // in, or the number of `tokenOut` tokens the Pool will send out, depending on the given swap `kind`.
    //
    // All other fields are not strictly necessary for most swaps, but are provided to support advanced scenarios in
    // some Pools.
    //
    // `poolId` is the ID of the Pool involved in the swap - this is useful for Pool contracts that implement more than
    // one Pool.
    //
    // The meaning of `lastChangeBlock` depends on the Pool specialization:
    //  - Two Token or Minimal Swap Info: the last block in which either `tokenIn` or `tokenOut` changed its total
    //    balance.
    //  - General: the last block in which *any* of the Pool's registered tokens changed its total balance.
    //
    // `from` is the origin address for the funds the Pool receives, and `to` is the destination address
    // where the Pool sends the outgoing tokens.
    //
    // `userData` is extra data provided by the caller - typically a signature from a trusted party.

    /**
     * @dev Performs all `swaps`, calling swap hooks on the Pool contracts and updating their balances. Does not cause
     * any transfer of tokens - instead it returns the net Vault token deltas: positive if the Vault should receive
     * tokens, and negative if it should send them.
     */
    function _swapWithPools(
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        SwapKind kind
    ) private returns (int256[] memory assetDeltas) {
        assetDeltas = new int256[](assets.length);

        // These variables could be declared inside the loop, but that causes the compiler to allocate memory on each
        // loop iteration, increasing gas costs.
        BatchSwapStep memory batchSwapStep;
        SwapRequest memory poolRequest;

        // These store data about the previous swap here to implement multihop logic across swaps.
        IERC20Upgradeable previousTokenCalculated;
        uint256 previousAmountCalculated;

        for (uint256 i = 0; i < swaps.length; ++i) {
            batchSwapStep = swaps[i];

            bool withinBounds = batchSwapStep.assetInIndex < assets.length &&
                batchSwapStep.assetOutIndex < assets.length;
            require(withinBounds, "Out of bounds");

            IERC20Upgradeable tokenIn = IERC20Upgradeable(
                address(assets[batchSwapStep.assetInIndex])
            );
            IERC20Upgradeable tokenOut = IERC20Upgradeable(
                address(assets[batchSwapStep.assetOutIndex])
            );
            require(tokenIn != tokenOut, "Cannot swap same token");

            // Sentinel value for multihop logic
            if (batchSwapStep.amount == 0) {
                // When the amount given is zero, we use the calculated amount for the previous swap, as long as the
                // current swap's given token is the previous calculated token. This makes it possible to swap a
                // given amount of token A for token B, and then use the resulting token B amount to swap for token C.
                require(i > 0, "Unknown amount in first swap");
                bool usingPreviousToken = previousTokenCalculated ==
                    _tokenGiven(kind, tokenIn, tokenOut);
                require(usingPreviousToken, "Malconstructed multihop swap");
                batchSwapStep.amount = previousAmountCalculated;
            }

            // Initializing each struct field one-by-one uses less gas than setting all at once
            poolRequest.poolId = batchSwapStep.poolId;
            poolRequest.kind = kind;
            poolRequest.tokenIn = tokenIn;
            poolRequest.tokenOut = tokenOut;
            poolRequest.amount = batchSwapStep.amount;
            poolRequest.userData = batchSwapStep.userData;
            poolRequest.from = funds.sender;
            poolRequest.to = funds.recipient;
            // The lastChangeBlock field is left uninitialized

            uint256 amountIn;
            uint256 amountOut;
            (previousAmountCalculated, amountIn, amountOut) = _swapWithPool(
                poolRequest
            );

            previousTokenCalculated = _tokenCalculated(kind, tokenIn, tokenOut);

            // Accumulate Vault deltas across swaps
            assetDeltas[batchSwapStep.assetInIndex] =
                assetDeltas[batchSwapStep.assetInIndex] +
                amountIn.toInt256();
            assetDeltas[batchSwapStep.assetOutIndex] =
                assetDeltas[batchSwapStep.assetOutIndex] -
                amountOut.toInt256();
        }
    }

    /**
     * @dev Returns true if `asset` is the sentinel value that represents ETH.
     */
    function _isETH(IAsset asset) internal pure returns (bool) {
        return address(asset) == _ETH;
    }

    /**
     * @dev Translates `asset` into an equivalent IERC20Upgradeable token address. If `asset` represents ETH, it will be translated
     * to the WETH contract.
     */
    function _translateToIERC20(
        IAsset asset
    ) internal view returns (IERC20Upgradeable) {
        return
            _isETH(asset)
                ? IERC20Upgradeable(address(_WETH()))
                : _asIERC20(asset);
    }

    /**
     * @dev Same as `_translateToIERC20(IAsset)`, but for an entire array.
     */
    function _translateToIERC20(
        IAsset[] memory assets
    ) internal view returns (IERC20Upgradeable[] memory) {
        IERC20Upgradeable[] memory tokens = new IERC20Upgradeable[](
            assets.length
        );
        for (uint256 i = 0; i < assets.length; ++i) {
            tokens[i] = _translateToIERC20(assets[i]);
        }
        return tokens;
    }

    /**
     * @dev Interprets `asset` as an IERC20Upgradeable token. This function should only be called on `asset` if `_isETH` previously
     * returned false for it, that is, if `asset` is guaranteed not to be the ETH sentinel value.
     */
    function _asIERC20(IAsset asset) internal pure returns (IERC20Upgradeable) {
        return IERC20Upgradeable(address(asset));
    }

    /**
     * @dev Performs a swap according to the parameters specified in `request`, calling the Pool's contract hook and
     * updating the Pool's balance.
     *
     * Returns the amount of tokens going into or out of the Vault as a result of this swap, depending on the swap kind.
     */
    function _swapWithPool(
        SwapRequest memory request
    )
        internal
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut)
    {
        // Get the calculated amount from the Pool and update its balances
        if (request.kind == SwapKind.GIVEN_IN) {
            amountCalculated = _getAmountOut(
                request.poolId,
                request.amount,
                address(request.tokenIn),
                address(request.tokenOut)
            );
            amountIn = request.amount;
            amountOut = amountCalculated;
        } else {
            // SwapKind.GIVEN_OUT
            amountCalculated = _getAmountOut(
                request.poolId,
                request.amount,
                address(request.tokenOut),
                address(request.tokenIn)
            );
            amountIn = amountCalculated;
            amountOut = request.amount;
        }
        poolBalances[request.poolId][address(request.tokenIn)] += amountIn;
        poolBalances[request.poolId][address(request.tokenOut)] -= amountOut;

        emit Swap(
            request.poolId,
            request.tokenIn,
            request.tokenOut,
            amountIn,
            amountOut
        );
    }

    function _getAmountOut(
        bytes32 poolId_,
        uint256 fromAmount_,
        address fromToken_,
        address toToken_
    ) internal view returns (uint256) {
        uint256 reserveFrom_ = getTokenBalance(poolId_, fromToken_);
        uint256 reserveTo = getTokenBalance(poolId_, toToken_);
        return
            reserveTo -
            (reserveFrom_ * reserveTo) /
            (reserveFrom_ + fromAmount_);
    }

    function _authenticateFor(address user) internal view {
        require(msg.sender == user, "!Balancer Authorized");
    }

    function _WETH() internal view returns (IWETH) {
        return weth;
    }
}
