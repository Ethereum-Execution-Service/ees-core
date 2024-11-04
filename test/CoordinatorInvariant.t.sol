// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {console} from "forge-std/src/console.sol";
import {CoordinatorWrapper} from "./actors/CoordinatorWrapper.sol";
import {MockCoordinator} from "./mocks/MockCoordinator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {DummyJobRegistry} from "./mocks/dummyContracts/DummyJobRegistry.sol";
import {ICoordinator} from "../src/interfaces/ICoordinator.sol";
contract CoordinatorInvariant is Test {
  CoordinatorWrapper public coordinatorWrapper;

  function setUp() public {
    coordinatorWrapper = new CoordinatorWrapper();
    targetContract(address(coordinatorWrapper));

    bytes4[] memory selectors = new bytes4[](7);
    selectors[0] = CoordinatorWrapper.stake.selector;
    selectors[1] = CoordinatorWrapper.unstake.selector;
    selectors[2] = CoordinatorWrapper.topup.selector;
    selectors[3] = CoordinatorWrapper.withdrawProtocolBalance.selector;
    selectors[4] = CoordinatorWrapper.executeBatch.selector;
    selectors[5] = CoordinatorWrapper.slashCommitter.selector;
    selectors[6] = CoordinatorWrapper.slashInactiveExecutor.selector;

    targetSelector(
      FuzzSelector({
        addr: address(coordinatorWrapper),
        selectors: selectors
      })
    );
  }

  
  function invariant_coordinatorTokenBalance() public view {
    // all executor balances + protocol balance should be equal to token balance of coordinator
    uint256 totalExecutorBalances = coordinatorWrapper.getTotalExecutorBalances();
    uint256 protocolBalance = coordinatorWrapper.getProtocolBalance();
    uint256 nextEpochPoolBalance = coordinatorWrapper.getNextEpochPoolBalance();
    assertEq(totalExecutorBalances + protocolBalance + nextEpochPoolBalance, coordinatorWrapper.getCoordinatorBalance());
  }

  function invariant_tokensInSystemEqualTotalStakedMinusTotalUnstaked() public view {
    // that has been staked minus what has been unstaked should be within the systems balances
    uint256 totalStaked = coordinatorWrapper.getTotalStaked();
    uint256 totalUnstaked = coordinatorWrapper.getTotalUnstaked();
    assertEq(totalStaked - totalUnstaked, coordinatorWrapper.getTotalExecutorBalances() + coordinatorWrapper.getProtocolBalance() + coordinatorWrapper.getTreasuryBalance() + coordinatorWrapper.getNextEpochPoolBalance());
  }

  function invariant_noGapsInActiveExecutorsArray() public view {
    assertFalse(coordinatorWrapper.gapsInActiveExecutorsArray());
  }
  
}
