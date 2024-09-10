// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAutoPayQuerier} from "./interfaces/IAutoPayQuerier.sol";
import {AutoPay} from "./applications/AutoPay.sol";
import {IAutoPay} from "./interfaces/applications/IAutoPay.sol";
import {IJobRegistry} from "./interfaces/IJobRegistry.sol";
import {IApplication} from "./interfaces/IApplication.sol";
import {Querier} from "./Querier.sol";
import {IQuerier} from "./interfaces/IQuerier.sol";

contract AutoPayQuerier is IAutoPayQuerier {
    AutoPay autoPay;
    Querier querier;

    constructor(AutoPay _autoPay, Querier _querier) {
        autoPay = _autoPay;
        querier = _querier;
    }

    function getData(uint256[] calldata _indices) public view override returns (Data[] memory) {
        Data[] memory data = new Data[](_indices.length);
        IQuerier.JobData[] memory jobsData = querier.getJobs(_indices);
        for (uint256 i; i < _indices.length;) {
            uint256 index = _indices[i];
            (address recipient, uint256 amount, address token, bytes12 amountFactors) = autoPay.payments(index);
            IAutoPay.PaymentData memory paymentData =
                IAutoPay.PaymentData({recipient: recipient, amount: amount, token: token, amountFactors: amountFactors});
            data[i] = Data({jobData: jobsData[i], paymentData: paymentData});
            unchecked {
                ++i;
            }
        }

        return data;
    }
}
