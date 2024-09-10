// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "solmate/src/tokens/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/utils/Base64.sol";
import {AutoPayQuerier} from "../AutoPayQuerier.sol";
import {IAutoPayQuerier} from "../interfaces/IAutoPayQuerier.sol";

contract PayNFT is ERC721 {
    uint256 public currentTokenId;

    address autoPay;
    AutoPayQuerier public autoPayQuerier;

    address public paymentRecipient = 0x8bCAC48d9cC2075917e1F1A831Df954214f7d6f9;
    address public paymentToken = 0x7139F4601480d20d43Fa77780B67D295805aD31a;
    // 5 USDC
    uint256 public paymentAmount = 5000000;

    uint32 public minCooldown = 2592000;

    mapping(address => bool) public hasMinted;

    error NonExistentTokenURI();
    error NotSubscribed();
    error AlreadyMinted();
    error NotOwnerOfJob();
    error ApplicationNotPay();
    error NotRecurringExecutionModule();
    error NeedAtleastOnePayment();
    error NotCorrectAmount();
    error NotCorrectCooldown();
    error NotCorrectRecipient();
    error NotCorrectToken();
    error NotCorrectAmountFactors();

    constructor(string memory _name, string memory _symbol, address _autoPay, address _autoPayQuerier)
        ERC721(_name, _symbol)
    {
        autoPay = _autoPay;
        autoPayQuerier = AutoPayQuerier(_autoPayQuerier);
    }

    function mint(uint256 _jobIndex) public payable returns (uint256) {
        // get job data
        uint256[] memory jobIndices = new uint256[](1);
        jobIndices[0] = _jobIndex;
        IAutoPayQuerier.Data memory data = autoPayQuerier.getData(jobIndices)[0];
        if (data.jobData.owner != msg.sender) {
            revert NotOwnerOfJob();
        }
        if (address(data.jobData.application) != autoPay) {
            revert ApplicationNotPay();
        }
        if (data.jobData.executionModule != 0x01) {
            revert NotRecurringExecutionModule();
        }
        if (data.jobData.executionCounter == 0) {
            revert NeedAtleastOnePayment();
        }

        (, uint32 cooldown) = abi.decode(data.jobData.executionModuleData, (uint40, uint32));

        if (data.paymentData.amount < paymentAmount) {
            revert NotCorrectAmount();
        }

        if (cooldown < minCooldown) {
            revert NotCorrectCooldown();
        }

        if (data.paymentData.recipient != paymentRecipient) {
            revert NotCorrectRecipient();
        }
        if (data.paymentData.token != paymentToken) {
            revert NotCorrectToken();
        }

        if (data.paymentData.amountFactors != 0x000000000000000000000000) {
            revert NotCorrectAmountFactors();
        }

        if (hasMinted[msg.sender]) {
            revert AlreadyMinted();
        }
        uint256 newItemId = ++currentTokenId;
        _safeMint(msg.sender, newItemId);
        hasMinted[msg.sender] = true;
        return newItemId;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert NonExistentTokenURI();
        }

        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name": "EES Pay Subscribed #',
                    Strings.toString(tokenId),
                    '", "description": "EES Pay Subscribed NFT',
                    '", "image": "ipfs://QmWSt81F7PsVDnK1gWPMH7oxExm7zhzYWYhBUYirMnzdoW"}'
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }
}
