// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";

contract FeeManager is IFeeManager, Owned {
    uint32 public constant BASE_BPS = 1_000_000;

    // like uniswap, 3000 = 0.3% etc
    uint16 public treasuryFeeBasisPoints;
    address internal treasury;

    constructor(address _owner, address _treasury, uint16 _treasuryFeeBasisPoints) Owned(_owner) {
        treasury = _treasury;
        treasuryFeeBasisPoints = _treasuryFeeBasisPoints;
    }

    // Function to calculate fee and remaining amount
    function calculateFee(uint256 _amount, uint16 _basisPoints) public pure override returns (uint256 fee) {
        // Calculate fee
        fee = (_amount * _basisPoints) / BASE_BPS;

        return fee;
    }

    function setTreasuryFeeBasisPoints(uint16 _treasuryFeeBasisPoints) public override onlyOwner {
        treasuryFeeBasisPoints = _treasuryFeeBasisPoints;
    }

    function setTreasury(address _treasury) public override onlyOwner {
        treasury = _treasury;
    }
}
