// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

contract TestCustomHealthCheck {
    uint256 public profitLimit;
    uint256 public lossLimit;
    uint256 public debtPaymentLimit;
    uint256 public debtOutstandingLimit;

    address public governance;
    address public management;

    mapping(address => address) public checks;

    modifier onlyGovernance() {
        require(msg.sender == governance, "!Authorized");
        _;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == governance || msg.sender == management,
            "!Authorized"
        );
        _;
    }

    constructor(
        uint256 profitLimit_,
        uint256 lossLimit_,
        uint256 debtPaymentLimit_,
        uint256 debtOutstandingLimit_
    ) {
        governance = msg.sender;
        management = msg.sender;
        profitLimit = profitLimit_;
        lossLimit = lossLimit_;
        debtPaymentLimit = debtPaymentLimit_;
        debtOutstandingLimit = debtOutstandingLimit_;
    }

    function setGovernance(address governance_) external onlyGovernance {
        require(governance_ != address(0), "Invalid address");
        governance = governance_;
    }

    function setManagement(address management_) external onlyGovernance {
        require(management_ != address(0), "Invalid address");
        management = management_;
    }

    function setProfitLimit(uint256 profitLimit_) external onlyAuthorized {
        profitLimit = profitLimit_;
    }

    function setLossLimit(uint256 lossLimit_) external onlyAuthorized {
        lossLimit = lossLimit_;
    }

    function setDebtPaymentLimit(
        uint256 debtPaymentLimit_
    ) external onlyAuthorized {
        debtPaymentLimit = debtPaymentLimit_;
    }

    function setDebtOutstandingLimit(
        uint256 debtOutstandingLimit_
    ) external onlyAuthorized {
        debtOutstandingLimit = debtOutstandingLimit_;
    }

    function check(
        uint256 profit_,
        uint256 loss_,
        uint256 debtPayment_,
        uint256 debtOutstanding_,
        address
    ) external view returns (bool) {
        if (profit_ > profitLimit) {
            return false;
        }
        if (loss_ > lossLimit) {
            return false;
        }
        if (debtPayment_ > debtPaymentLimit) {
            return false;
        }
        if (debtOutstanding_ > debtOutstandingLimit) {
            return false;
        }
        return true;
    }
}
