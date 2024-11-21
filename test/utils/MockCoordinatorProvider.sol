// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Coordinator} from "../../src/Coordinator.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";

// crates a generic coordinator for testing
contract MockCoordinatorProvider is TokenProvider {
    MockCoordinator coordinator;

    constructor(address _treasury) {
        initializeERC20Tokens();
        ICoordinator.InitSpec memory spec = ICoordinator.InitSpec({
            stakingToken: address(token0),
            stakingAmountPerModule: 500,
            minimumStakingPeriod: 2,
            stakingBalanceThreshold: 300,
            inactiveSlashingAmount: 200,
            commitSlashingAmount: 50,
            roundDuration: 15,
            roundsPerEpoch: 5,
            roundBuffer: 15,
            commitPhaseDuration: 15,
            revealPhaseDuration: 15,
            slashingDuration: 30,
            executionTax: 4,
            protocolPoolCutBps: 1000
        });
        coordinator = new MockCoordinator(spec, _treasury);
    }

    function getMockCoordinator() external view returns (address) {
        return address(coordinator);
    }

}
