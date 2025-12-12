// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IExecutionModule} from "../interfaces/IExecutionModule.sol";
import {IPeggedLinearAuction} from "../interfaces/feeModules/IPeggedLinearAuction.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {Coordinator} from "../Coordinator.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/**
 * @title PeggedLinearAuction
 * @notice Fee module that implements a linear auction pricing model pegged to base fee and execution tax
 * @dev The execution fee is calculated based on block.basefee and execution tax, scaled by a linear
 *      overhead multiplier that increases from minOverheadBps to maxOverheadBps over the execution window.
 *      During the zero fee window, execution is free. Uses a price oracle to convert between tokens.
 */
contract PeggedLinearAuction is IPeggedLinearAuction {
    /// @notice The Coordinator contract that manages this fee module
    Coordinator public immutable coordinator;

    /// @notice Mapping from job index to fee parameters (token, oracle, overhead bounds, oracle data)
    mapping(uint256 => Params) public params;

    /// @notice Gas overhead constant used in fee calculations (100,000 gas)
    uint256 private constant _GAS_OVERHEAD = 100_000;

    /// @notice Basis points denominator (10,000 = 100%)
    uint256 private constant _BASE_BPS = 10_000;

    /**
     * @notice Initializes the PeggedLinearAuction fee module
     * @param _coordinator The Coordinator contract address
     */
    constructor(Coordinator _coordinator) {
        coordinator = _coordinator;
    }

    /**
     * @notice Ensures only registered JobRegistry contracts can call module functions
     * @dev Reverts if msg.sender is not a registered JobRegistry in the Coordinator
     */
    modifier onlyJobRegistry() {
        if (!coordinator.isJobRegistry(msg.sender)) revert NotJobRegistry();
        _;
    }

    /**
     * @notice Computes the execution fee based on base fee, execution tax, and linear overhead
     * @dev During the zero fee window, returns 0. After the zero fee window, calculates fee as:
     *      executionFee = totalTax + (baseFeeCost * overheadBps / 10000)
     *      where overheadBps increases linearly from minOverheadBps to maxOverheadBps over the execution window.
     *      Uses price oracle to convert between tax token and execution fee token.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _executionWindow The total execution window duration (in seconds)
     * @param _zeroFeeWindow The duration of the zero fee period at the start (in seconds)
     * @param _executionTime The timestamp from which execution is allowed
     * @param _variableGasConsumption The gas consumption of the job execution (used in fee calculation)
     * @return executionFee The computed execution fee in the fee token
     * @return executionFeeToken The token address for the execution fee
     * @return inZeroFeeWindow True if execution is within the zero fee window
     */
    function onExecuteJob(
        uint256 _index,
        uint24 _executionWindow,
        uint24 _zeroFeeWindow,
        uint256 _executionTime,
        uint256 _variableGasConsumption
    )
        external
        override
        onlyJobRegistry
        returns (uint256 executionFee, address executionFeeToken, bool inZeroFeeWindow)
    {
        Params memory job = params[_index];
        executionFeeToken = job.executionFeeToken;

        if (block.timestamp - _executionTime < _zeroFeeWindow) {
            executionFee = 0;
            inZeroFeeWindow = true;
        } else {
            // else calculate fee as a linear function between minOverheadBps and maxOverheadBps of base fee plus tax over _executionWindow, starting from _zeroFeeWindow
            (address taxToken, uint256 executionTax, uint256 protocolPoolCutBps) = coordinator.getTaxConfig();

            // get tak token decimals
            uint8 taxTokenDecimals = ERC20(taxToken).decimals();

            // tokens per 1 eth in tokenDecimals and tokens per 1 USD in tokenDecimals
            (uint256 priceInETH, uint256 priceInUSD) = job.priceOracle.getPrice(job.executionFeeToken, job.oracleData);

            // we have to scale executorTax and protocolTax to feeTokenDecimals
            // should we just do this in the oracle? Since this is the only place we use priceInUSD

            // total tax in fee tokens and fee token decimals
            uint256 totalTax = (priceInUSD * executionTax) / taxTokenDecimals;

            // wei / gas
            uint256 baseFee = block.basefee;
            // gas
            uint256 totalGasConsumption = _variableGasConsumption + _GAS_OVERHEAD;

            // we have to scale price from per ETH to per wei basis, so div by 10**18
            // number of tokens to pay for base fee in fee token decimals
            uint256 totalFeeBase = (priceInETH * baseFee * totalGasConsumption) / 10 ** 18;

            uint256 feeDiff;
            uint256 windowDiff;
            unchecked {
                feeDiff = job.maxOverheadBps - job.minOverheadBps;
                windowDiff = _executionWindow - _zeroFeeWindow - 1;
            }

            uint256 secondsAfterZeroFeeWindow = block.timestamp - (_executionTime + _zeroFeeWindow);
            // calculate fee overhead as linear function between min and max over execution window
            // reaches maxExecutionFee at _executionTime + _executionWindow - 1, the last timestep that the job can be executed
            uint256 feeOverheadBps = ((feeDiff * secondsAfterZeroFeeWindow) / windowDiff) + job.minOverheadBps;

            // return execution fee in fee tokens and fee token address
            executionFee = totalTax + ((totalFeeBase * feeOverheadBps) / _BASE_BPS);
            inZeroFeeWindow = false;
        }
    }

    /**
     * @notice Stores the fee parameters for a job when it is created
     * @dev Decodes the input bytes to extract executionFeeToken, priceOracle, minOverheadBps,
     *      maxOverheadBps, and oracleData. Validates that minOverheadBps <= maxOverheadBps.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _inputs ABI-encoded parameters: (address executionFeeToken, IPriceOracle priceOracle,
     *                uint48 minOverheadBps, uint48 maxOverheadBps, bytes oracleData)
     * @custom:reverts MinExecutionFeeGreaterThanMax if minOverheadBps > maxOverheadBps
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
     * @notice Deletes the fee parameters for a job when it is deleted
     * @param _index The index of the job in the jobs array in JobRegistry contract
     */
    function onDeleteJob(uint256 _index) external onlyJobRegistry {
        delete params[_index];
    }

    /**
     * @notice Updates the fee parameters for an existing job
     * @dev Decodes the input bytes and updates the stored parameters. Validates that minOverheadBps <= maxOverheadBps.
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @param _inputs ABI-encoded parameters: (address executionFeeToken, IPriceOracle priceOracle,
     *                uint48 minOverheadBps, uint48 maxOverheadBps, bytes oracleData)
     * @custom:reverts MinExecutionFeeGreaterThanMax if minOverheadBps > maxOverheadBps
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
     * @notice Returns the encoded parameters for a job
     * @param _index The index of the job in the jobs array in JobRegistry contract
     * @return encodedData ABI-encoded parameters: (executionFeeToken, priceOracle, minOverheadBps, maxOverheadBps, oracleData)
     */
    function getEncodedData(uint256 _index) public view override returns (bytes memory) {
        Params memory param = params[_index];
        return abi.encode(
            param.executionFeeToken, param.priceOracle, param.minOverheadBps, param.maxOverheadBps, param.oracleData
        );
    }

    /**
     * @notice Returns the gas overhead constant used in fee calculations
     * @return gasOverhead The gas overhead value (100,000 gas)
     */
    function getGasOverhead() external pure override returns (uint256) {
        return _GAS_OVERHEAD;
    }
}
