// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/src/Test.sol";
import {SignatureGenerator} from "../utils/SignatureGenerator.sol";
import {MockERC1271} from "../mocks/MockERC1271.sol";
import {PublicERC6492Validator} from "../../src/PublicERC6492Validator.sol";

contract SignatureVerificationTest is Test, SignatureGenerator {
    PublicERC6492Validator publicERC6492Validator;

    address signer;
    uint256 signerPrivateKey;

    function setUp() public {
        publicERC6492Validator = new PublicERC6492Validator();
        signerPrivateKey = 0x12341234;
        signer = vm.addr(signerPrivateKey);
    }

    // isValidSignatureNowAllowSideEffects(address account, bytes32 hash, bytes calldata signature)

    function test_VerifyValidSignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        vm.assertTrue(publicERC6492Validator.isValidSignatureNowAllowSideEffects(signer, msgHash, sig));
    }

    function test_VerifyValidCompactSignature(bytes32 msgHash) public {
        bytes memory sig = generateCompactSignature(msgHash, signerPrivateKey);
        vm.assertTrue(publicERC6492Validator.isValidSignatureNowAllowSideEffects(signer, msgHash, sig));
    }

    function test_TooLongSignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        bytes memory sigExtra = bytes.concat(sig, bytes1(uint8(1)));
        assertEq(sigExtra.length, 66);
        vm.assertFalse(publicERC6492Validator.isValidSignatureNowAllowSideEffects(signer, msgHash, sigExtra));
    }

    function test_NonEOASignature(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        MockERC1271 mockERC1271 = new MockERC1271();
        mockERC1271.setReturnValidSignature(true);
        address nonEOASigner = address(mockERC1271);
        vm.assertTrue(publicERC6492Validator.isValidSignatureNowAllowSideEffects(nonEOASigner, msgHash, sig));
    }

    function test_NonEOASignatureWrong(bytes32 msgHash) public {
        bytes memory sig = generateSignature(msgHash, signerPrivateKey);
        MockERC1271 mockERC1271 = new MockERC1271();
        address nonEOASigner = address(mockERC1271);
        vm.assertFalse(publicERC6492Validator.isValidSignatureNowAllowSideEffects(nonEOASigner, msgHash, sig));
    }

    function test_InvalidSigner(bytes32 msgHash, uint256 privateKey) public {
        vm.assume(signerPrivateKey != privateKey);
        privateKey =
            bound(privateKey, 1, 115792089237316195423570985008687907852837564279074904382605163141518161494336);
        bytes memory sig = generateSignature(msgHash, privateKey);
        vm.assertFalse(publicERC6492Validator.isValidSignatureNowAllowSideEffects(signer, msgHash, sig));
    }

    function test_InvalidSignature(bytes32 msgHash) public {
        bytes memory malformedSig = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));
        vm.assertFalse(publicERC6492Validator.isValidSignatureNowAllowSideEffects(signer, msgHash, malformedSig));
    }
}
