// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/src/Test.sol";
import {MockJobRegistry} from "./mocks/MockJobRegistry.sol";
import {MockCoordinatorProvider} from "./utils/MockCoordinatorProvider.sol";
import {MockCoordinator} from "./mocks/MockCoordinator.sol";
import {PublicERC6492Validator} from "../src/PublicERC6492Validator.sol";
import {IJobRegistry} from "../src/interfaces/IJobRegistry.sol";

contract NonceBitmapTest is Test {
    MockJobRegistry jobRegistry;

    function setUp() public {
        MockCoordinatorProvider coordinatorProvider = new MockCoordinatorProvider(address(0x3));
        MockCoordinator coordinator = MockCoordinator(coordinatorProvider.getMockCoordinator());
        PublicERC6492Validator publicERC6492Validator = new PublicERC6492Validator();
        jobRegistry = new MockJobRegistry(coordinator, publicERC6492Validator);
    }

    function test_LowNonces() public {
        jobRegistry.useUnorderedNonce(address(this), 5, true);
        jobRegistry.useUnorderedNonce(address(this), 0, true);
        jobRegistry.useUnorderedNonce(address(this), 1, true);

        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 1, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 5, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 0, true);
        jobRegistry.useUnorderedNonce(address(this), 4, true);
    }

    function test_NonceWordBoundary() public {
        jobRegistry.useUnorderedNonce(address(this), 255, true);
        jobRegistry.useUnorderedNonce(address(this), 256, true);

        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 255, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 256, true);
    }

    function test_HighNonces() public {
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240, true);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240 + 1, true);

        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240 + 1, true);
    }

    function test_InvalidateFullWord() public {
        jobRegistry.invalidateUnorderedNonces(0, 2 ** 256 - 1);

        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 0, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 1, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 254, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 255, true);
        jobRegistry.useUnorderedNonce(address(this), 256, true);
    }

    function test_InvalidateNonzeroWord() public {
        jobRegistry.invalidateUnorderedNonces(1, 2 ** 256 - 1);

        jobRegistry.useUnorderedNonce(address(this), 0, true);
        jobRegistry.useUnorderedNonce(address(this), 254, true);
        jobRegistry.useUnorderedNonce(address(this), 255, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 256, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 511, true);
        jobRegistry.useUnorderedNonce(address(this), 512, true);
    }

    function test_UsingNonceTwiceFails(uint256 nonce) public {
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
    }

    function test_UseTwoRandomNonces(uint256 first, uint256 second) public {
        jobRegistry.useUnorderedNonce(address(this), first, true);
        if (first == second) {
            vm.expectRevert(IJobRegistry.InvalidNonce.selector);
            jobRegistry.useUnorderedNonce(address(this), second, true);
        } else {
            jobRegistry.useUnorderedNonce(address(this), second, true);
        }
    }

    function test_InvalidateNoncesRandomly(uint248 wordPos, uint256 mask) public {
        jobRegistry.invalidateUnorderedNonces(wordPos, mask);
        assertEq(mask, jobRegistry.nonceBitmap(address(this), wordPos));
    }

    function test_InvalidateTwoNoncesRandomly(uint248 wordPos, uint256 startBitmap, uint256 mask) public {
        jobRegistry.invalidateUnorderedNonces(wordPos, startBitmap);
        assertEq(startBitmap, jobRegistry.nonceBitmap(address(this), wordPos));

        // invalidating with the mask changes the original bitmap
        uint256 finalBitmap = startBitmap | mask;
        jobRegistry.invalidateUnorderedNonces(wordPos, mask);
        uint256 savedBitmap = jobRegistry.nonceBitmap(address(this), wordPos);
        assertEq(finalBitmap, savedBitmap);

        // invalidating with the same mask should do nothing
        jobRegistry.invalidateUnorderedNonces(wordPos, mask);
        assertEq(savedBitmap, jobRegistry.nonceBitmap(address(this), wordPos));
    }

    function test_ReuseNonce(uint256 nonce) public {
        jobRegistry.useUnorderedNonce(address(this), nonce, false);
        jobRegistry.useUnorderedNonce(address(this), nonce, false);
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
    }

    function test_ConsumeReusableNonce(uint256 nonce) public {
        jobRegistry.useUnorderedNonce(address(this), nonce, false);
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
    }
    
    function test_InvalidateReusableNonce(uint256 nonce) public {
        jobRegistry.useUnorderedNonce(address(this), nonce, false);
        uint256 wordPos = nonce / 256;
        uint256 mask = 1 << (nonce % 256);
        jobRegistry.invalidateUnorderedNonces(wordPos, mask);
        vm.expectRevert(IJobRegistry.InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), nonce, true);
    }
    
}
