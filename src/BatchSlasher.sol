// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ICoordinator} from "./interfaces/ICoordinator.sol";

contract BatchSlasher {
    ICoordinator public coordinator;

    constructor(address _coordinator) {
        coordinator = ICoordinator(_coordinator);
    }

    function batchSlash(
        address[] calldata _committerExecutors,
        address[] calldata _inactiveExecutors,
        uint8[] calldata _rounds,
        address _recipient
    ) external {
        // inactiveExecutors.length and rounds.length must be the same, otherwise it will panic and revert

        // loop thorugh inactiveExecutors and call slashInactiveExecutor
        for (uint256 i = 0; i < _inactiveExecutors.length; i++) {
            try coordinator.slashInactiveExecutor(_inactiveExecutors[i], _rounds[i], _recipient) {} catch {}
        }

        // loop through committerExecutors and call slashCommitter
        for (uint256 i = 0; i < _committerExecutors.length; i++) {
            try coordinator.slashCommitter(_committerExecutors[i], _recipient) {} catch {}
        }
    }
}
