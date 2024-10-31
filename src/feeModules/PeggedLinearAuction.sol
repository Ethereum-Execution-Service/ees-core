// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IExecutionModule} from "../interfaces/IExecutionModule.sol";
import {IPeggedLinearAuction} from "../interfaces/feeModules/IPeggedLinearAuction.sol";
import {JobRegistry} from "../JobRegistry.sol";
import {IJobRegistry} from "../interfaces/IJobRegistry.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {Coordinator} from "../Coordinator.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @author Victor Brevig
contract PeggedLinearAuction is IPeggedLinearAuction {
    JobRegistry public immutable jobRegistry;
    Coordinator public immutable coordinator;
    mapping(uint256 => Params) public params;

    uint256 private constant _GAS_OVERHEAD = 100_000;
    uint256 private constant _BASE_BPS = 10_000;

    constructor(JobRegistry _jobRegistry, Coordinator _coordinator) {
        jobRegistry = _jobRegistry;
        coordinator = _coordinator;
    }

    modifier onlyJobRegistry() {
        if (msg.sender != address(jobRegistry)) revert NotJobRegistry();
        _;
    }

    /**
     * @notice Computes execution fee as the block.basefee scaled by an overhead determined by linear function between minOverheadBps and maxOverheadBps depending on time in execution window.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _executionWindow The amount of time the job can be executed within.
     * @param _executionTime The time the job can be executed from.
     * @param _variableGasConsumption The gas consumption of the job execution.
     * @return executionFee The computed execution fee.
     * @return executionFeeToken The token address of the execution fee.
     */
    function onExecuteJob(
        uint256 _index,
        uint32 _executionWindow,
        uint256 _executionTime,
        uint256 _variableGasConsumption
    ) external override onlyJobRegistry returns (uint256 executionFee, address executionFeeToken) {
        Params memory job = params[_index];

        (address taxToken, uint256 protocolTax, uint256 executorTax) = coordinator.getTaxConfig();
        
        // get tak token decimals
        uint8 taxTokenDecimals = ERC20(taxToken).decimals();

        // tokens per 1 eth in tokenDecimals and tokens per 1 USD in tokenDecimals
        (uint256 priceInETH, uint256 priceInUSD) = job.priceOracle.getPrice(job.executionFeeToken, job.oracleData);

        // we have to scale executorTax and protocolTax to feeTokenDecimals
        // should we just do this in the oracle? Since this is the only place we use priceInUSD

        // total tax in fee tokens and fee token decimals
        uint256 totalTax = (priceInUSD * (executorTax + protocolTax)) / taxTokenDecimals;

        // wei / gas
        uint256 baseFee = block.basefee;
        // gas
        uint256 totalGasConsumption = _variableGasConsumption + _GAS_OVERHEAD;

        // we have to scale price from per ETH to per wei basis, so div by 10**18
        // number of tokens to pay for base fee in fee token decimals
        uint256 totalFeeBase = (priceInETH * baseFee * totalGasConsumption) / 10**18;

        uint256 feeDiff;
        unchecked {
            feeDiff = job.maxOverheadBps - job.minOverheadBps;
        }

        uint256 secondsInExecutionWindow = block.timestamp - _executionTime;
        // calculate fee overhead as linear function between min and max over execution window
        uint256 feeOverheadBps = ((feeDiff * secondsInExecutionWindow) / (_executionWindow - 1)) + job.minOverheadBps;

        // return execution fee in fee tokens and fee token address
        executionFee = totalTax + ((totalFeeBase * feeOverheadBps) / _BASE_BPS);
        executionFeeToken = job.executionFeeToken;
    }

    /**
     * @notice Stores the parameters for a job in the params mapping.
     * @notice Reverts if minOverheadBps is greater than maxOverheadBps.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _inputs The encoded parameters for the job.
     */
    function onCreateJob(uint256 _index, bytes calldata _inputs) external override onlyJobRegistry {
        address executionFeeToken;
        IPriceOracle priceOracle;
        uint48 minOverheadBps;
        uint48 maxOverheadBps;
        bytes memory oracleData;
        (executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData) =
            abi.decode(_inputs, (address, IPriceOracle, uint48, uint48, bytes));

        if (minOverheadBps > maxOverheadBps) revert MinExecutionFeeGreaterThanMax();

        params[_index] = Params({
            executionFeeToken: executionFeeToken,
            priceOracle: priceOracle,
            minOverheadBps: minOverheadBps,
            maxOverheadBps: maxOverheadBps,
            oracleData: oracleData
        });
    }

    /**
     * @notice Deletes the parameters for a job in the params mapping.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice Updates the parameters for a job in the params mapping.
     * @notice Reverts if minOverheadBps is greater than maxOverheadBps.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @param _inputs The encoded parameters for the job.
     */
    function onUpdateData(uint256 _index, bytes calldata _inputs) external override onlyJobRegistry {
        address executionFeeToken;
        IPriceOracle priceOracle;
        uint48 minOverheadBps;
        uint48 maxOverheadBps;
        bytes memory oracleData;
        (executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData) =
            abi.decode(_inputs, (address, IPriceOracle, uint48, uint48, bytes));

        if (minOverheadBps > maxOverheadBps) revert MinExecutionFeeGreaterThanMax();

        Params storage job = params[_index];
        job.executionFeeToken = executionFeeToken;
        job.priceOracle = priceOracle;
        job.minOverheadBps = minOverheadBps;
        job.maxOverheadBps = maxOverheadBps;
        job.oracleData = oracleData;
    }

    /**
     * @notice Returns the encoded parameters for a job.
     * @param _index The index of the job in the jobs array in JobRegistry contract.
     * @return encodedData The encoded parameters for the job.
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(
            param.executionFeeToken, param.priceOracle, param.minOverheadBps, param.maxOverheadBps, param.oracleData
        );
    }

    /**
     * @notice Returns the gas overhead of calling onExecuteJob.
     * @return gasOverhead The gas overhead of calling onExecuteJob.
     */
    function getGasOverhead() external pure override returns (uint256) {
        return _GAS_OVERHEAD;
    }
}
