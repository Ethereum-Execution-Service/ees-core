// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {JobRegistry} from "./JobRegistry.sol";
import {IBatchExecutor} from "./interfaces/IBatchExecutor.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";

/// @author Victor Brevig
contract BatchExecutor is IBatchExecutor {
    JobRegistry public immutable jobRegistry;

    constructor(JobRegistry _jobRegistry) {
        jobRegistry = _jobRegistry;
    }

    function executeBatch(uint256[] calldata _jobIndices, address _feeRecipient, bytes[] calldata _verificationData)
        public
        override
        returns (Receipt[] memory)
    {
        Receipt[] memory receipts = new Receipt[](_jobIndices.length);
        for (uint256 i; i < _jobIndices.length;) {
            try jobRegistry.execute(_jobIndices[i], _feeRecipient, _verificationData[i]) returns (
                uint256 executionFee, address executionFeeToken
            ) {
                receipts[i] = Receipt({
                    jobIndex: _jobIndices[i],
                    executionFee: executionFee,
                    executionFeeToken: executionFeeToken
                });
            } catch (bytes memory revertData) {
                emit FailedExecution(_jobIndices[i], revertData);
            }
            unchecked {
                ++i;
            }
        }
        return receipts;
    }
}
