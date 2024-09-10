// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {MockJobRegistry} from "./mocks/MockJobRegistry.sol";
import {SignatureVerification} from "../src/libraries/SignatureVerification.sol";
import {SignatureGenerator} from "./utils/SignatureGenerator.sol";
import {MockERC1271} from "./mocks/MockERC1271.sol";

contract Verifier {
    using SignatureVerification for bytes;

    constructor() {}

    function verifySig(bytes calldata signature, bytes32 hash, address claimedSigner) public view {
        signature.verify(hash, claimedSigner);
    }
}

contract SignatureVerificationTest is Test, SignatureGenerator, Verifier {
    using SignatureVerification for bytes;

    Verifier verifier;

    address signer;
    uint256 signerPrivateKey;

    function setUp() public {
        verifier = new Verifier();
        signerPrivateKey = 0x12341234;
        signer = vm.addr(signerPrivateKey);
    }

    function test_VerifyValidSignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        verifier.verifySig(sig, msgHash, signer);
    }

    function test_VerifyValidCompactSignature(bytes32 msgHash) public {
        bytes memory sig = generateCompactSignature(msgHash, signerPrivateKey);
        verifier.verifySig(sig, msgHash, signer);
    }

    function test_TooLongSignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        bytes memory sigExtra = bytes.concat(sig, bytes1(uint8(1)));
        assertEq(sigExtra.length, 66);
        vm.expectRevert(SignatureVerification.InvalidSignatureLength.selector);
        verifier.verifySig(sigExtra, msgHash, signer);
    }

    function test_NonEOASignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        MockERC1271 mockERC1271 = new MockERC1271();
        mockERC1271.setReturnValidSignature(true);
        address nonEOASigner = address(mockERC1271);
        verifier.verifySig(sig, msgHash, nonEOASigner);
    }

    function test_NonEOASignatureWrong(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        MockERC1271 mockERC1271 = new MockERC1271();
        address nonEOASigner = address(mockERC1271);
        vm.expectRevert(SignatureVerification.InvalidContractSignature.selector);
        verifier.verifySig(sig, msgHash, nonEOASigner);
    }

    function test_InvalidSigner(bytes32 msgHash, uint256 privateKey) public {
        vm.assume(signerPrivateKey != privateKey);
        privateKey =
            bound(privateKey, 1, 115792089237316195423570985008687907852837564279074904382605163141518161494336);
        bytes memory sig = generateSignature(msgHash, privateKey);
        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        verifier.verifySig(sig, msgHash, signer);
    }

    function test_InvalidSignature(bytes32 msgHash) public {
        bytes memory malformedSig = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));
        vm.expectRevert(SignatureVerification.InvalidSignature.selector);
        verifier.verifySig(malformedSig, msgHash, signer);
    }
}
