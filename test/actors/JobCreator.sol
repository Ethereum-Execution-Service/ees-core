// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {MockJobRegistry} from "../mocks/MockJobRegistry.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract JobCreator is Test {
    MockJobRegistry jobRegistry;
    MockERC20 token;

    constructor(MockJobRegistry _jobRegistry, MockERC20 _token) {
        jobRegistry = _jobRegistry;
        token = _token;
    }

    function createJobNewIndex(uint256 _index) public {
    }

    function createJobExistingIndex(uint256 _index) public {
    }


    

}
