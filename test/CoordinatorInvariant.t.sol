// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {console} from "forge-std/src/console.sol";
import {CoordinatorHandler} from "./handlers/CoordinatorHandler.sol";
import {MockCoordinator} from "./mocks/MockCoordinator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {DummyJobRegistry} from "./mocks/dummyContracts/DummyJobRegistry.sol";
import {ICoordinator} from "../src/interfaces/ICoordinator.sol";
contract CoordinatorInvariant is Test {
  CoordinatorHandler public coordinatorHandler;

  function setUp() public {
    coordinatorHandler = new CoordinatorHandler();
    targetContract(address(coordinatorHandler));

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = CoordinatorHandler.stake.selector;
    selectors[1] = CoordinatorHandler.unstake.selector;
    selectors[2] = CoordinatorHandler.topup.selector;
    selectors[3] = CoordinatorHandler.withdrawProtocolBalance.selector;
    selectors[4] = CoordinatorHandler.executeBatch.selector;
    selectors[5] = CoordinatorHandler.slashCommitter.selector;
    selectors[6] = CoordinatorHandler.slashInactiveExecutor.selector;

    targetSelector(
      FuzzSelector({
        addr: address(coordinatorHandler),
        selectors: selectors
      })
    );
  }

  
  function invariant_coordinatorTokenBalance() public view {
    // all executor balances + protocol balance should be equal to token balance of coordinator
    uint256 totalExecutorBalances = coordinatorHandler.getTotalExecutorBalances();
    uint256 protocolBalance = coordinatorHandler.getProtocolBalance();
    uint256 nextEpochPoolBalance = coordinatorHandler.getNextEpochPoolBalance();
    assertEq(totalExecutorBalances + protocolBalance + nextEpochPoolBalance, coordinatorHandler.getCoordinatorBalance());
  }

  function invariant_tokensInSystemEqualTotalStakedMinusTotalUnstaked() public view {
    // that has been staked minus what has been unstaked should be within the systems balances
    uint256 totalStaked = coordinatorHandler.getTotalStaked();
    uint256 totalUnstaked = coordinatorHandler.getTotalUnstaked();
    assertEq(totalStaked - totalUnstaked, coordinatorHandler.getTotalExecutorBalances() + coordinatorHandler.getProtocolBalance() + coordinatorHandler.getTreasuryBalance() + coordinatorHandler.getNextEpochPoolBalance());
  }

  function invariant_noGapsInActiveExecutorsArray() public view {
    assertFalse(coordinatorHandler.gapsInActiveExecutorsArray());
  }

  function invariant_numberOfInitializedExecutorsGeActive() public view {
    (uint256 initializedExecutors, uint256 activeExecutors) = coordinatorHandler.getNumberOfInitializedAndActiveExecutors();
    assertGe(initializedExecutors, activeExecutors);
  }

  function invariant_poolCutReceiversArray() public view {
    if(coordinatorHandler.getTotalNumberOfExecutedJobsCreatedBeforeEpoch() > 0) {
      assertGt(coordinatorHandler.getPoolCutReceiversLength(), 0);
    } else {
      assertEq(coordinatorHandler.getPoolCutReceiversLength(), 0);
    }
    if(coordinatorHandler.getTotalNumberOfExecutedJobsCreatedBeforeEpoch() > 0) {
      assertGt(coordinatorHandler.getPoolCutReceiversLength(), 0);
    } else {
      assertEq(coordinatorHandler.getPoolCutReceiversLength(), 0);
    }
  }

  function invariant_executorsWithRoundInfoInPoolCutReceivers() public view {
    assertTrue(coordinatorHandler.getExecutorsWithRoundInfoInPoolCutReceivers());
  }
}
