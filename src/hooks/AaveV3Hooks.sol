// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";

contract AaveV3Hooks is IBeforeTransaction {
    bytes4 constant L1_WITHDRAW_SELECTOR = 0x69328dec;
    bytes4 constant L1_SUPPLY_SELECTOR = 0x617ba037;

    address public immutable fund;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund) {
        fund = _fund;
    }

    function checkBeforeTransaction(address, bytes4 selector, uint8, uint256, bytes calldata data)
        external
        view
        override
    {
        require(msg.sender == fund, "only fund");

        address asset;
        address onBehalfOf;

        if (selector == L1_SUPPLY_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }
        } else if (selector == L1_WITHDRAW_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }
        } else {
            revert("unsupported selector");
        }

        require(assetWhitelist[asset], "asset not enabled");
        require(onBehalfOf == fund, "only fund");
    }

    function enableAsset(address asset) external {
        require(msg.sender == fund, "only fund");
        assetWhitelist[asset] = true;
    }

    function disableAsset(address asset) external {
        require(msg.sender == fund, "only fund");
        assetWhitelist[asset] = false;
    }
}
