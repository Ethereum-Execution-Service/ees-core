// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAutoPay} from "../interfaces/applications/IAutoPay.sol";
import {FeeManager} from "../FeeManager.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IApplication} from "../interfaces/IApplication.sol";
import {JobRegistry} from "../JobRegistry.sol";

contract AutoPay is IAutoPay, IApplication, FeeManager {
    using SafeTransferLib for ERC20;

    JobRegistry public immutable jobRegistry;

    uint256 internal AMOUNT_BASE = 10_000;

    mapping(uint256 => PaymentData) public payments;

    modifier onlyJobRegistry() {
        if (msg.sender != address(jobRegistry)) revert NotJobRegistry();
        _;
    }

    constructor(JobRegistry _jobRegistry, address _treasury, uint16 _treasuryBasisPoints, address _owner)
        FeeManager(_owner, _treasury, _treasuryBasisPoints)
    {
        jobRegistry = _jobRegistry;
    }

    function onCreateJob(uint256 _index, bytes1 _executionModule, address _owner, bytes calldata _inputs)
        external
        override
        onlyJobRegistry
    {
        address recipient;
        uint256 amount;
        address token;
        bytes12 amountFactors;
        assembly {
            recipient := calldataload(_inputs.offset)
            amount := calldataload(add(_inputs.offset, 0x20))
            token := calldataload(add(_inputs.offset, 0x40))
            amountFactors := calldataload(add(_inputs.offset, 0x60))

            let numberFactors := byte(0, amountFactors)
            // Ensure the number of groups does not exceed the maximum allowed
            if gt(numberFactors, 3) { revert(0, 0) }
        }

        PaymentData memory payment =
            PaymentData({recipient: recipient, amount: amount, token: token, amountFactors: amountFactors});

        payments[_index] = payment;

        emit PaymentCreated(_index, recipient);
    }

    function onDeleteJob(uint256 _index, address _owner) external override onlyJobRegistry {
        PaymentData memory payment = payments[_index];
        delete payments[_index];
        emit PaymentCanceled(_index, payment.recipient);
    }

    function onExecuteJob(uint256 _index, address _owner, uint48 _executionNumber) external override onlyJobRegistry {
        PaymentData memory payment = payments[_index];

        uint16 factor = findFactor(payment.amountFactors, _executionNumber);
        uint256 amount = (payment.amount * factor) / AMOUNT_BASE;

        uint256 protocolFee = calculateFee(amount, treasuryFeeBasisPoints);
        uint256 remainingAmount = amount - protocolFee;

        // transfer protocol fee
        ERC20(payment.token).safeTransferFrom(_owner, treasury, protocolFee);
        // transfer amount
        ERC20(payment.token).safeTransferFrom(_owner, payment.recipient, remainingAmount);

        emit Payment(_index, _owner, payment.recipient, _executionNumber, payment.amount, payment.token, protocolFee, 1);
    }

    function findFactor(bytes12 data, uint48 executionNumber) public pure returns (uint16 factor) {
        assembly {
            let numOfFactors := byte(0, data)
            let lastNumIndex := mul(numOfFactors, 3)
            let returnDefault := or(iszero(numOfFactors), gt(executionNumber, byte(lastNumIndex, data)))
            if returnDefault { factor := 10000 }
            if iszero(returnDefault) {
                // Loop through each group
                for { let i := lastNumIndex } gt(i, 2) { i := sub(i, 3) } {
                    let num := byte(i, data)
                    if gt(executionNumber, num) {
                        factor := or(shl(8, byte(add(i, 4), data)), byte(add(i, 5), data))
                        //factor := and(shr(mul(add(i, 4), 8), data), 0xFFFF)
                        break
                    }
                    if eq(executionNumber, num) {
                        factor := or(shl(8, byte(add(i, 1), data)), byte(add(i, 2), data))
                        //factor := and(shr(mul(add(i, 1), 8), data), 0xFFFF)
                        break
                    }
                }
            }
        }
    }
}
