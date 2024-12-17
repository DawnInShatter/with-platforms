// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {BytesLib} from "./BytesLib.sol";

/// @title Functions for manipulating path data for multihop swaps
library Path {
    using BytesLib for bytes;

    /// @dev The length of the bytes encoded address
    uint256 private constant _ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded fee
    uint256 private constant _FEE_SIZE = 3;

    /// @dev The offset of a single token address and pool fee
    uint256 private constant _NEXT_OFFSET = _ADDR_SIZE + _FEE_SIZE;
    /// @dev The offset of an encoded pool key
    uint256 private constant _POP_OFFSET = _NEXT_OFFSET + _ADDR_SIZE;
    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint256 private constant _MULTIPLE_POOLS_MIN_LENGTH =
        _POP_OFFSET + _NEXT_OFFSET;

    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= _MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        return ((path.length - _ADDR_SIZE) / _NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    /// @return fee The fee level of the pool
    function decodeFirstPool(
        bytes memory path
    ) internal pure returns (address tokenA, address tokenB, uint24 fee) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(_ADDR_SIZE);
        tokenB = path.toAddress(_NEXT_OFFSET);
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(
        bytes memory path
    ) internal pure returns (bytes memory) {
        return path.slice(0, _POP_OFFSET);
    }

    /// @notice Skips a token + fee element from the buffer and returns the remainder
    /// @param path The swap path
    /// @return The remaining token + fee elements in the path
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(_NEXT_OFFSET, path.length - _NEXT_OFFSET);
    }
}
