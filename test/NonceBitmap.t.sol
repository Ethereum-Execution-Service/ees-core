// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {MockJobRegistry} from "./mocks/MockJobRegistry.sol";
import {InvalidNonce} from "../src/PermitErrors.sol";

contract NonceBitmapTest is Test {
    MockJobRegistry jobRegistry;

    function setUp() public {
        jobRegistry = new MockJobRegistry(address(0x2), address(0x3), 2);
    }

    function testLowNonces() public {
        jobRegistry.useUnorderedNonce(address(this), 5);
        jobRegistry.useUnorderedNonce(address(this), 0);
        jobRegistry.useUnorderedNonce(address(this), 1);

        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 1);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 5);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 0);
        jobRegistry.useUnorderedNonce(address(this), 4);
    }

    function testNonceWordBoundary() public {
        jobRegistry.useUnorderedNonce(address(this), 255);
        jobRegistry.useUnorderedNonce(address(this), 256);

        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 255);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 256);
    }

    function testHighNonces() public {
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240 + 1);

        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 2 ** 240 + 1);
    }

    function testInvalidateFullWord() public {
        jobRegistry.invalidateUnorderedNonces(0, 2 ** 256 - 1);

        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 0);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 1);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 254);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 255);
        jobRegistry.useUnorderedNonce(address(this), 256);
    }

    function testInvalidateNonzeroWord() public {
        jobRegistry.invalidateUnorderedNonces(1, 2 ** 256 - 1);

        jobRegistry.useUnorderedNonce(address(this), 0);
        jobRegistry.useUnorderedNonce(address(this), 254);
        jobRegistry.useUnorderedNonce(address(this), 255);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 256);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), 511);
        jobRegistry.useUnorderedNonce(address(this), 512);
    }

    function testUsingNonceTwiceFails(uint256 nonce) public {
        jobRegistry.useUnorderedNonce(address(this), nonce);
        vm.expectRevert(InvalidNonce.selector);
        jobRegistry.useUnorderedNonce(address(this), nonce);
    }

    function testUseTwoRandomNonces(uint256 first, uint256 second) public {
        jobRegistry.useUnorderedNonce(address(this), first);
        if (first == second) {
            vm.expectRevert(InvalidNonce.selector);
            jobRegistry.useUnorderedNonce(address(this), second);
        } else {
            jobRegistry.useUnorderedNonce(address(this), second);
        }
    }

    function testInvalidateNoncesRandomly(uint248 wordPos, uint256 mask) public {
        jobRegistry.invalidateUnorderedNonces(wordPos, mask);
        assertEq(mask, jobRegistry.nonceBitmap(address(this), wordPos));
    }

    function testInvalidateTwoNoncesRandomly(uint248 wordPos, uint256 startBitmap, uint256 mask) public {
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
}
