// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {JobRegistry} from "../src/JobRegistry.sol";

// forge test --match-contract EIP712
contract EIP712Test is Test {
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("JobRegistry");

    JobRegistry jobRegistry;

    function setUp() public {
        jobRegistry = new JobRegistry(address(0x2), address(0x2), 2);
    }

    function testDomainSeparator() public {
        bytes32 expectedDomainSeparator =
            keccak256(abi.encode(TYPE_HASH, NAME_HASH, block.chainid, address(jobRegistry)));

        assertEq(jobRegistry.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    function testDomainSeparatorAfterFork() public {
        bytes32 beginningSeparator = jobRegistry.DOMAIN_SEPARATOR();
        uint256 newChainId = block.chainid + 1;
        vm.chainId(newChainId);
        assertTrue(jobRegistry.DOMAIN_SEPARATOR() != beginningSeparator);

        bytes32 expectedDomainSeparator = keccak256(abi.encode(TYPE_HASH, NAME_HASH, newChainId, address(jobRegistry)));
        assertEq(jobRegistry.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }
}
