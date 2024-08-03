// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "@src/libs/Errors.sol";
import "@src/interfaces/ITransactionHooks.sol";
import "@src/interfaces/ITransactionModule.sol";
import "./Structs.sol";
import {BP_DIVISOR} from "@src/libs/Constants.sol";

contract TransactionModule is ReentrancyGuard, ITransactionModule {
    address public immutable fund;
    IHookRegistry public immutable hookRegistry;
    uint256 public maxGasPriorityInBasisPoints;
    bool public paused;

    modifier onlyFund() {
        if (msg.sender != fund) revert Errors.OnlyFund();
        _;
    }

    modifier notPaused() {
        if (paused) revert Errors.Transaction_ModulePaused();
        _;
    }

    /// TODO: calculate the gas overhead of the refunding logic so we can refund the correct amount of gas
    modifier refundGasToCaller() {
        uint256 gasAtStart = gasleft();

        /// failsafe for caller not to be able to set a gas price that is too high
        /// the fund can update this limit in moments of emergency (e.g. high gas prices, network congestion, etc.)
        /// gasPriority = tx.gasprice - block.basefee
        /// @dev the chain must be EIP1559 complient to support `basefee`
        if (
            maxGasPriorityInBasisPoints > 0 && tx.gasprice > block.basefee
                && ((tx.gasprice - block.basefee) * BP_DIVISOR) / tx.gasprice
                    >= maxGasPriorityInBasisPoints
        ) {
            revert Errors.Transaction_GasLimitExceeded();
        }

        _;

        if (
            /// the refund will not be exact but we can get close
            !ISafe(fund).execTransactionFromModule(
                msg.sender, (gasAtStart - gasleft()) * tx.gasprice, "", Enum.Operation.Call
            )
        ) {
            revert Errors.Transaction_GasRefundFailed();
        }
    }

    constructor(address owner, address _hookRegistry) {
        fund = owner;
        hookRegistry = IHookRegistry(_hookRegistry);
    }

    function setMaxGasPriorityInBasisPoints(uint256 newMaxGasPriorityInBasisPoints)
        external
        onlyFund
    {
        maxGasPriorityInBasisPoints = newMaxGasPriorityInBasisPoints;
    }

    function _executeAndReturnDataOrRevert(
        address target,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnData) =
            ISafe(fund).execTransactionFromModuleReturnData(target, value, data, operation);

        if (!success) {
            assembly {
                /// bubble up revert reason if length > 0
                if gt(mload(returnData), 0) { revert(add(returnData, 0x20), mload(returnData)) }
                /// else revert with no reason
                revert(0, 0)
            }
        }

        return returnData;
    }

    /**
     * @dev Sends multiple transactions and reverts all if one fails.
     * @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
     *                     operation as a uint8 with 0 for a call or 1 for a delegatecall (=> 1 byte),
     *                     to as a address (=> 20 bytes),
     *                     value as a uint256 (=> 32 bytes),
     *                     data length as a uint256 (=> 32 bytes),
     *                     data as bytes.
     *                     see abi.encodePacked for more information on packed encoding
     * @notice This method is payable as delegatecalls keep the msg.value from the previous call
     *         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
     */
    function execute(Transaction[] calldata transactions)
        external
        nonReentrant
        refundGasToCaller
        notPaused
    {
        uint256 transactionCount = transactions.length;

        /// @notice min transaction length is 85 bytes (a single function selector with no calldata)
        if (transactionCount == 0) revert Errors.Transaction_InvalidTransactionLength();

        /// lets iterate over the transactions. Each transaction will be verified and then executed through the safe.
        for (uint256 i = 0; i < transactionCount;) {
            /// msg.sender is operator
            Hooks memory hook = hookRegistry.getHooks(
                msg.sender,
                transactions[i].target,
                transactions[i].operation,
                transactions[i].targetSelector
            );

            if (!hook.defined) {
                revert Errors.Transaction_HookNotDefined();
            }

            if (hook.beforeTrxHook != address(0)) {
                _executeAndReturnDataOrRevert(
                    /// target
                    hook.beforeTrxHook,
                    /// value
                    0,
                    /// data
                    abi.encodeWithSelector(
                        IBeforeTransaction.checkBeforeTransaction.selector,
                        transactions[i].target,
                        transactions[i].targetSelector,
                        transactions[i].operation,
                        transactions[i].value,
                        transactions[i].data
                    ),
                    /// operation
                    Enum.Operation.Call
                );
            }

            bytes memory returnData = _executeAndReturnDataOrRevert(
                transactions[i].target,
                transactions[i].value,
                abi.encodePacked(transactions[i].targetSelector, transactions[i].data),
                transactions[i].operation == uint8(Enum.Operation.DelegateCall)
                    ? Enum.Operation.DelegateCall
                    : Enum.Operation.Call
            );

            if (hook.afterTrxHook != address(0)) {
                _executeAndReturnDataOrRevert(
                    hook.afterTrxHook,
                    0,
                    abi.encodeWithSelector(
                        IAfterTransaction.checkAfterTransaction.selector,
                        transactions[i].target,
                        transactions[i].targetSelector,
                        transactions[i].operation,
                        transactions[i].value,
                        transactions[i].data,
                        returnData
                    ),
                    Enum.Operation.Call
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    function pause() external onlyFund {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyFund {
        paused = false;

        emit Unpaused();
    }
}
