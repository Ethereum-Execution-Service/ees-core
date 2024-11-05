// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {MockCoordinator} from "../mocks/MockCoordinator.sol";
import {TokenProvider} from "../utils/TokenProvider.sol";
import {ICoordinator} from "../../src/interfaces/ICoordinator.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Executor} from "./Executor.sol";
import {DummyJobRegistry} from "../mocks/dummyContracts/DummyJobRegistry.sol";

contract CoordinatorWrapper is Test, TokenProvider {
  MockCoordinator coordinator;
  TokenProvider tokenProvider;
  DummyJobRegistry jobRegistry;
  Executor[] public executors;

  uint256 public totalProtocolWithdrawalAmount;

  event TokensInitialized();

  constructor() {
    initializeERC20Tokens();
    emit TokensInitialized();
    ICoordinator.InitSpec memory spec = ICoordinator.InitSpec({
      stakingToken: address(token0),
      stakingAmount: 1000,
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
      executorTax: 2,
      protocolTax: 2
    });
    coordinator = new MockCoordinator(spec, address(0x5));
    jobRegistry = new DummyJobRegistry();
    vm.prank(address(0x5));
    coordinator.setJobRegistry(address(jobRegistry));
    coordinator.initiateEpoch();
  }

  function stake() public {
    Executor executor = new Executor(coordinator);
    // first make sure account has tokens
    setERC20TestTokens(address(executor));
    setERC20TestTokenApprovals(vm, address(executor), address(coordinator));
    executors.push(executor);
    executor.stake();
  }

  function unstake(uint256 index) public {
    if (executors.length == 0) return;
    index = bound(index, 0, executors.length - 1);

    // if executor is not initialized, stake. This is to avoid further useless tests for this executor.
    (,,bool initialized,,,,,) = coordinator.executorInfo(address(executors[index]));
    if (!initialized) {
      executors[index].stake();
    }

    executors[index].unstake();
  }

  function topup(uint256 amount, uint256 index) public {
    if (executors.length == 0) return;
    index = bound(index, 0, executors.length - 1);
    
    // if executor is not initialized, stake. This is to avoid further useless tests for this executor.
    (uint256 stakingBalance,,bool initialized,,,,,) = coordinator.executorInfo(address(executors[index]));
    if (!initialized) {
      executors[index].stake();
    }
    uint256 stakingAmount = coordinator.getStakingAmount();
    // Bound amount between minimum required and max available
    if (stakingBalance < stakingAmount) {
        uint256 minRequired = stakingAmount - stakingBalance;
        amount = bound(amount, minRequired, token0.balanceOf(address(executors[index])) / 1000);
    } else {
        amount = bound(amount, 0, token0.balanceOf(address(executors[index])) / 1000);
    }
    
    executors[index].topup(amount);
  }

  function executeBatch(uint256 index, bool revertOnExecute) public {
    if (executors.length == 0) return;
    index = bound(index, 0, executors.length - 1);
    
    // if executor is not initialized, stake. If not active, topup.
    (uint256 stakingBalance,bool active,bool initialized,,,,,) = coordinator.executorInfo(address(executors[index]));
    if (!initialized) {
      executors[index].stake();
    }
    else if (!active) {
      uint256 stakingAmount = coordinator.getStakingAmount();
      if (stakingBalance < stakingAmount) {
        executors[index].topup(stakingAmount - stakingBalance);
      }
    }
    // now when executor is both active and initialized, we can execute
    if (revertOnExecute) {
      jobRegistry.setRevertOnExecute(true);
    }
    executors[index].executeBatch();
    if (revertOnExecute) {
      jobRegistry.setRevertOnExecute(false);
    }
  }

  function slashCommitter(uint256 index, uint256 slashIndex) public {
    if (executors.length == 0) return;
    index = bound(index, 0, executors.length - 1);
    slashIndex = bound(slashIndex, 0, executors.length - 1);

    // if executor is not initialized, stake. If not active, topup.
    (uint256 stakingBalance,bool active,bool initialized,,,,,) = coordinator.executorInfo(address(executors[index]));
    if (!initialized) {
      executors[index].stake();
    }
    else if (!active) {
      uint256 stakingAmount = coordinator.getStakingAmount();
      if (stakingBalance < stakingAmount) {
        executors[index].topup(stakingAmount - stakingBalance);
      }
    }

    // executor to slash should also be active and initialized
    (uint256 stakingBalanceSlash,bool activeSlash,bool initializedSlash,,,,,) = coordinator.executorInfo(address(executors[slashIndex]));
    if (!initializedSlash) {
      executors[slashIndex].stake();
    }
    else if (!activeSlash) {
      uint256 stakingAmount = coordinator.getStakingAmount();
      if (stakingBalanceSlash < stakingAmount) {
        executors[slashIndex].topup(stakingAmount - stakingBalanceSlash);
      }
    }
    executors[slashIndex].slashCommitter(address(executors[index]));
  }

  function slashInactiveExecutor(uint256 index, uint256 slashIndex, uint8 round) public {
    if (executors.length == 0) return;
    index = bound(index, 0, executors.length - 1);
    slashIndex = bound(slashIndex, 0, executors.length - 1);
    round = uint8(bound(round, 0, coordinator.getRoundsPerEpoch() - 1));

    // if executor is not initialized, stake. If not active, topup.
    (uint256 stakingBalance,bool active,bool initialized,,,,,) = coordinator.executorInfo(address(executors[index]));
    if (!initialized) {
      executors[index].stake();
    }
    else if (!active) {
      uint256 stakingAmount = coordinator.getStakingAmount();
      if (stakingBalance < stakingAmount) {
        executors[index].topup(stakingAmount - stakingBalance);
      }
    }

    // executor to slash should also be active and initialized
    (uint256 stakingBalanceSlash,bool activeSlash,bool initializedSlash,,,,,) = coordinator.executorInfo(address(executors[slashIndex]));
    if (!initializedSlash) {
      executors[slashIndex].stake();
    }
    else if (!activeSlash) {
      uint256 stakingAmount = coordinator.getStakingAmount();
      if (stakingBalanceSlash < stakingAmount) {
        executors[slashIndex].topup(stakingAmount - stakingBalanceSlash);
      }
    }
    executors[slashIndex].slashInactiveExecutor(address(executors[index]), round);
  }


  function getTotalExecutorBalances() public view returns (uint256) {
    uint256 totalBalance;
    for (uint256 i = 0; i < executors.length; i++) {
      (uint256 balance,,,,,,,) = coordinator.executorInfo(address(executors[i]));
      totalBalance += balance;
    }
    return totalBalance;
  }

  function getCoordinatorBalance() public view returns (uint256) {
    return token0.balanceOf(address(coordinator));
  }

  function getTotalExecutorStaked() public view returns (uint256) {
    uint256 totalStaked;
    for (uint256 i = 0; i < executors.length; i++) {
      totalStaked += executors[i].amountStaked();
    }
    return totalStaked;
  }

  function getTotalExecutorUnstaked() public view returns (uint256) {
    uint256 totalUnstaked;
    for (uint256 i = 0; i < executors.length; i++) {
      totalUnstaked += executors[i].amountUnstaked();
    }
    return totalUnstaked;
  }

  function withdrawProtocolBalance() public {
    vm.prank(address(0x5));
    totalProtocolWithdrawalAmount += coordinator.withdrawProtocolBalance();
  }

  function getProtocolBalance() public view returns (uint256) {
    return coordinator.getProtocolBalance();
  }

  function getTreasuryBalance() public view returns (uint256) {
    return token0.balanceOf(address(0x5));
  }

  function getTotalStaked() public view returns (uint256) {
    uint256 totalStaked;
    for (uint256 i = 0; i < executors.length; i++) {
      totalStaked += executors[i].amountStaked();
    }
    return totalStaked;
  }

  function getTotalUnstaked() public view returns (uint256) {
    uint256 totalUnstaked;
    for (uint256 i = 0; i < executors.length; i++) {
      totalUnstaked += executors[i].amountUnstaked();
    }
    return totalUnstaked;
  }

  function gapsInActiveExecutorsArray() public view returns (bool) {
    if (coordinator.getNumberOfActiveExecutors() == 0) return false;
    for (uint256 i = 0; i < coordinator.getNumberOfActiveExecutors() - 1; i++) {
      if (coordinator.activeExecutors(i) == address(0)) {
        return true;
      }
    }
    return false;
  }

  function getNextEpochPoolBalance() public view returns (uint256) {
    return coordinator.getNextEpochPoolBalance();
  }

  function getNumberOfInitializedAndActiveExecutors() public view returns (uint256, uint256) {
    uint256 initializedExecutors;
    uint256 activeExecutors;
    for (uint256 i = 0; i < executors.length; i++) {
      (,bool active,bool initialized,,,,,) = coordinator.executorInfo(address(executors[i]));
      if (initialized) initializedExecutors++;
      if (active) activeExecutors++;
    }
    return (initializedExecutors, activeExecutors);
  }

  function getPoolCutReceiversLength() public view returns (uint256) {
    return coordinator.getPoolCutReceiversLength();
  }

  function getTotalNumberOfExecutedJobsCreatedBeforeEpoch() public view returns (uint256) {
    return coordinator.getTotalNumberOfExecutedJobsCreatedBeforeEpoch();
  }
}
