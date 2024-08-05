// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";

import "@src/libs/Errors.sol";
import "@src/hooks/transfers/TokenTransferHooks.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {CALL} from "@src/libs/Constants.sol";

contract TestTokenTransferHooks is Test {
    TokenTransferHooks internal tokenTransferHooks;
    address internal fund;

    function setUp() public {
        fund = makeAddr("Fund");
        tokenTransferHooks = new TokenTransferHooks(fund);
    }

    function test_erc20_transfer(address token, address to, uint256 amount) public {
        vm.startPrank(fund);
        vm.expectRevert(TokenTransferHooks_TransferNotAllowed.selector);
        tokenTransferHooks.checkBeforeTransaction(
            token, IERC20.transfer.selector, CALL, amount, abi.encode(to, amount)
        );

        tokenTransferHooks.enableTransfer(token, to, fund, IERC20.transfer.selector);
        tokenTransferHooks.checkBeforeTransaction(
            token, IERC20.transfer.selector, CALL, amount, abi.encode(to, amount)
        );
        vm.stopPrank();
    }

    function test_erc20_transfer_from(address token, address from, address to, uint256 amount)
        public
    {
        vm.startPrank(fund);
        vm.expectRevert(TokenTransferHooks_TransferNotAllowed.selector);
        tokenTransferHooks.checkBeforeTransaction(
            token, IERC20.transferFrom.selector, CALL, amount, abi.encode(from, to, amount)
        );

        tokenTransferHooks.enableTransfer(token, to, from, IERC20.transferFrom.selector);
        tokenTransferHooks.checkBeforeTransaction(
            token, IERC20.transferFrom.selector, CALL, amount, abi.encode(from, to, amount)
        );
        vm.stopPrank();
    }

    function test_native_transfer(address to, uint256 amount) public {
        vm.assume(amount > 0);
        vm.label(to, "Recipient");

        vm.startPrank(fund);
        vm.expectRevert(TokenTransferHooks_TransferNotAllowed.selector);
        tokenTransferHooks.checkBeforeTransaction(
            to, NATIVE_ETH_TRANSFER_SELECTOR, CALL, amount, ""
        );

        vm.expectRevert(TokenTransferHooks_DataMustBeEmpty.selector);
        tokenTransferHooks.checkBeforeTransaction(
            to, NATIVE_ETH_TRANSFER_SELECTOR, CALL, amount, "0x1234"
        );

        vm.expectRevert(Errors.Hook_InvalidValue.selector);
        tokenTransferHooks.checkBeforeTransaction(to, NATIVE_ETH_TRANSFER_SELECTOR, CALL, 0, "");

        tokenTransferHooks.enableTransfer(NATIVE_ASSET, to, fund, NATIVE_ETH_TRANSFER_SELECTOR);
        tokenTransferHooks.checkBeforeTransaction(
            to, NATIVE_ETH_TRANSFER_SELECTOR, CALL, amount, ""
        );
        vm.stopPrank();
    }

    function test_only_fund_can_enable_transfer(
        address token,
        address to,
        address from,
        bytes4 selector
    ) public {
        vm.prank(makeAddr("NotFund"));
        vm.expectRevert(Errors.OnlyFund.selector);
        tokenTransferHooks.enableTransfer(token, to, from, selector);
    }

    function test_can_only_enable_transfer_for_valid_selector(
        address token,
        address to,
        address from,
        bytes4 selector
    ) public {
        vm.assume(selector != IERC20.transfer.selector);
        vm.assume(selector != IERC20.transferFrom.selector);
        vm.assume(selector != NATIVE_ETH_TRANSFER_SELECTOR);

        vm.prank(fund);
        vm.expectRevert(Errors.Hook_InvalidTargetSelector.selector);
        tokenTransferHooks.enableTransfer(token, to, from, selector);
    }

    function test_only_fund_can_disable_transfer(
        address token,
        address to,
        address from,
        bytes4 selector
    ) public {
        vm.prank(makeAddr("NotFund"));
        vm.expectRevert(Errors.OnlyFund.selector);
        tokenTransferHooks.disableTransfer(token, to, from, selector);
    }

    function test_only_fund_can_call_hook(
        address token,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes memory data,
        address notFund
    ) public {
        vm.assume(notFund != fund);

        vm.prank(notFund);
        vm.expectRevert(Errors.OnlyFund.selector);
        tokenTransferHooks.checkBeforeTransaction(token, selector, operation, value, data);
    }

    function test_operation_must_be_call(
        address token,
        bytes4 selector,
        uint256 value,
        bytes memory data,
        uint8 notCall
    ) public {
        vm.assume(notCall != CALL);

        vm.prank(fund);
        vm.expectRevert(Errors.Hook_InvalidOperation.selector);
        tokenTransferHooks.checkBeforeTransaction(token, selector, notCall, value, data);
    }
}