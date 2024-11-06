// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
//import {JobCreator} from "../actors/JobCreator.sol";
//import {JobSponsor} from "../actors/JobSponsor.sol";
import {MockJobRegistry} from "../mocks/MockJobRegistry.sol";

contract JobRegistryHandler is Test, TokenProvider {
    MockJobRegistry jobRegistry;
    //JobCreator[] public jobCreators;
    //JobSponsor[] public jobSponsors;


    constructor() {
        initializeERC20Tokens();
        jobRegistry = new MockJobRegistry(address(0x3), address(0x4));
    }
}
