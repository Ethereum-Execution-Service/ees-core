// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./Base.t.sol";
import {IJobRegistry} from "../../src/interfaces/IJobRegistry.sol";

/**
 * @notice Tests for the reveal function
 */
contract CoordinatorRevealTest is CoordinatorBaseTest {
    function test_Reveal(uint192 epochNum, uint256 time) public {
        // should reveal the commitment and set the seed
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration() - 1
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(time);
        vm.prank(executor);
        coordinator.reveal(sig);

        (,, bool revealed) = coordinator.commitmentMap(executor);
        assertTrue(revealed, "not revealed");
    }

    function test_RevealBeforeRevealPhase(uint256 time) public {
        // should revert with InvalidBlockTime if reveal phase has not started
        time = bound(time, 0, defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration - 1);
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.reveal(abi.encode(0));
    }

    function test_RevealAfterRevealPhase(uint256 time) public {
        // should revert with InvalidBlockTime if reveal phase has ended
        time = bound(
            time,
            defaultEpochEndTime - coordinator.getEpochDuration() + coordinator.getSelectionPhaseDuration(),
            type(uint256).max
        );
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        vm.warp(time);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidBlockTime.selector);
        coordinator.reveal(abi.encode(0));
    }

    function test_RevealWrongSigLength(uint192 epochNum) public {
        // should revert with InvalidSignatureLength if the signature is not 65 bytes
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);
        bytes memory sigExtra = abi.encodePacked(sig, uint8(1));

        coordinator.setCommitment(
            ICoordinator.CommitData({
                commitment: keccak256(abi.encodePacked(sigExtra)),
                epoch: epochNum,
                revealed: false
            }),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignatureLength.selector);
        coordinator.reveal(sigExtra);
    }

    function test_RevealWrongSigner(uint192 epochNum, address caller) public {
        // should revert with InvalidSignature if the signature is not from the signer
        vm.assume(executor != caller);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(caller);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(sig);
    }

    function test_RevealWrongEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        // should revert with OldEpoch if the epoch is not the current epoch
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(secondEpochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, secondExecutorPrivateKey));
    }

    function test_RevealWrongChainId(uint192 epochNum, uint256 chainId) public {
        // should revert with InvalidSignature if the signature is for a different chainId
        vm.assume(block.chainid != chainId);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, chainId));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epochNum, revealed: false}),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.InvalidSignature.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealWrongCommitment(uint192 epochNum, bytes32 commitment) public {
        // should revert with WrongCommitment if the commitment does not match the set commitment
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        vm.assume(commitment != keccak256(abi.encodePacked(sig)));

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: commitment, epoch: epochNum, revealed: false}), executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.WrongCommitment.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealCommitmentOldEpoch(uint192 epochNum, uint192 secondEpochNum) public {
        // should revert with OldEpoch if the set commitment epoch is not the current epoch
        vm.assume(epochNum != secondEpochNum);

        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epochNum, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({
                commitment: keccak256(abi.encodePacked(sig)),
                epoch: secondEpochNum,
                revealed: false
            }),
            executor
        );

        coordinator.setEpoch(epochNum);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.OldEpoch.selector);
        coordinator.reveal(generateSignature(ethSignedMessageHash, executorPrivateKey));
    }

    function test_RevealAlreadyRevealed(uint192 epoch) public {
        // should revert with CommitmentRevealed if the commitment has already been revealed this epoch
        vm.prank(executor);
        coordinator.stake(modulesToRegister);

        bytes32 msgHash = keccak256(abi.encodePacked(epoch, block.chainid));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        bytes memory sig = generateSignature(ethSignedMessageHash, executorPrivateKey);

        coordinator.setCommitment(
            ICoordinator.CommitData({commitment: keccak256(abi.encodePacked(sig)), epoch: epoch, revealed: true}),
            executor
        );

        coordinator.setEpoch(epoch);
        vm.warp(defaultEpochEndTime - coordinator.getEpochDuration() + commitPhaseDuration);
        vm.prank(executor);
        vm.expectRevert(ICoordinator.CommitmentRevealed.selector);
        coordinator.reveal(sig);
    }
}