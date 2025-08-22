// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024
pragma solidity ^0.8.10;

import {AbstractLiquidator, LiquidationResult, IntermediateData} from "./AbstractLiquidator.sol";
import {SiloFLTaker} from "./SiloFLTaker.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import {SiloFLTaker} from "./SiloFLTaker.sol";

contract SiloLiquidator is AbstractLiquidator {
    using SafeERC20 for IERC20;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public immutable siloFLTaker;

    modifier onlySilo(address token) {
        if (msg.sender != SiloFLTaker(siloFLTaker).tokenToSilo(token)) revert("Caller not Silo");
        _;
    }

    constructor(address _router, address _plb, address _siloFLTaker) AbstractLiquidator(_router, _plb) {
        siloFLTaker = _siloFLTaker;
    }

    function _takeFlashLoan(address token, uint256 amount, bytes memory data) internal virtual override {
        SiloFLTaker(siloFLTaker).takeFlashLoan(token, amount, data);
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        onlySilo(token)
        returns (bytes32)
    {
        if (initiator != siloFLTaker) revert("Flash loan initiator is not FLTaker");

        IntermediateData memory intData = abi.decode(data, (IntermediateData));

        _processFlashLoan(token, amount, fee, intData);

        IERC20(token).forceApprove(SiloFLTaker(siloFLTaker).tokenToSilo(token), amount + fee);

        return CALLBACK_SUCCESS;
    }
}
