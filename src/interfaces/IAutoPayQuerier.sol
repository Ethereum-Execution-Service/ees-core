// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IApplication} from "./IApplication.sol";
import {IQuerier} from "./IQuerier.sol";
import {IAutoPay} from "./applications/IAutoPay.sol";

interface IAutoPayQuerier {
    struct Data {
        IQuerier.JobData jobData;
        IAutoPay.PaymentData paymentData;
    }

    /// @notice Fetches job data  for all _indices along with the corresponding execution module data.
    /// @param _indices Array of indices of jobs to query data from.
    /// @return data Array of JobData structs containing information of the jobs. The job info for job at index _indices[i] will be stored in data[i].
    function getData(uint256[] calldata _indices) external view returns (Data[] memory);
}
