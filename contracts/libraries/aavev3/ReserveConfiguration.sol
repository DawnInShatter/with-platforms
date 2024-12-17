// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DataTypesV3} from "../../interfaces/aave/DataTypesV3.sol";

/**
 * @title ReserveConfiguration library
 * @author Aave
 * @notice Implements the bitmap logic to handle the reserve configuration
 */
library ReserveConfiguration {
    // solhint-disable-next-line
    uint256 internal constant VIRTUAL_ACC_ACTIVE_MASK =        0xEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    /**
     * @notice Gets the virtual account active/not state of the reserve
     * @dev The state should be true for all normal assets and should be false
     *  only in special cases (ex. GHO) where an asset is minted instead of supplied.
     * @param self The reserve configuration
     * @return The active state
     */
    function getIsVirtualAccActive(
        DataTypesV3.ReserveConfigurationMap memory self
    ) internal pure returns (bool) {
        return (self.data & ~VIRTUAL_ACC_ACTIVE_MASK) != 0;
    }
}
