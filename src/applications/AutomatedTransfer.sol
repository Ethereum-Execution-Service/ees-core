// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IApplication} from "../interfaces/IApplication.sol";
import {JobRegistry} from "../JobRegistry.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

contract AutomatedTransfer is IApplication, Owned {
    using SafeTransferLib for ERC20;

    struct TransferData {
        address recipient;
        uint256 amount;
        address token;
    }

    JobRegistry public immutable jobRegistry;

    mapping(uint256 => TransferData) public transferDataMapping;

    // could use a bit map here
    mapping(bytes1 => bool) public supportedExecutionModules;

    modifier onlyJobRegistry() {
        require(msg.sender == address(jobRegistry), "NotJobRegistry");
        _;
    }

    constructor(JobRegistry _jobRegistry) Owned(msg.sender) {
        jobRegistry = _jobRegistry;
        supportedExecutionModules[0x00] = true;
        supportedExecutionModules[0x01] = true;
    }

    function onCreateJob(uint256 _index, bytes1 _executionModule, address _owner, bytes calldata _inputs)
        external
        override
        onlyJobRegistry
    {
        require(supportedExecutionModules[_executionModule], "UnsupportedExecutionModule");
        (address recipient, uint256 amount, address token) = abi.decode(_inputs, (address, uint256, address));
        TransferData memory transferData = TransferData({recipient: recipient, amount: amount, token: token});
        transferDataMapping[_index] = transferData;
    }

    function onDeleteJob(uint256 _index, address _owner) external override onlyJobRegistry {
        delete transferDataMapping[_index];
    }

    function onExecuteJob(uint256 _index, address _owner, uint48 _executionNumber) external override onlyJobRegistry {
        TransferData memory transferData = transferDataMapping[_index];
        ERC20(transferData.token).safeTransferFrom(_owner, transferData.recipient, transferData.amount);
    }

    function changeExecutionModuleSupport(bytes1 _executionModule, bool _support) public onlyOwner {
        supportedExecutionModules[_executionModule] = _support;
    }
}
