// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFeeModule} from "../../../src/interfaces/IFeeModule.sol";
import {JobRegistry} from "../../../src/JobRegistry.sol";
import {IJobRegistry} from "../../../src/interfaces/IJobRegistry.sol";

contract DummyFeeModule is IFeeModule {
    uint256 public counter;

    address public executionFeeToken;
    uint256 public executionFee;

    constructor(address _executionFeeToken, uint256 _executionFee) {
        executionFeeToken = _executionFeeToken;
        executionFee = _executionFee;
        counter = 0;
    }

    function onCreateJob(uint256 _index, bytes calldata _inputs) external override {}

    function onDeleteJob(uint256 _index) external override {}

    function onExecuteJob(
        uint256 _index,
        uint24 _executionWindow,
        uint24 _zeroFeeWindow,
        uint256 _executionTime,
        uint256 _variableGasConsumption
    ) external override returns (uint256, address, bool) {
        counter++;
        return (executionFee, executionFeeToken, false);
    }

    function onUpdateData(uint256 _index, bytes calldata _inputs) public override {}

    function setExecutionFee(uint256 _executionFee) public {
        executionFee = _executionFee;
    }

    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        return "";
    }
}
