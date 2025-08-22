// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2023
pragma solidity ^0.8.17;

import {IAdapter} from "@gearbox-protocol/core-v2/contracts/interfaces/adapters/IAdapter.sol";

/// @title Euler V1 eToken adapter interface
/// @notice Implements logic allowing CAs to interact with Euler's eTokens
interface IEulerV1_ETokenAdapter is IAdapter {
    /// @notice Address of the eToken's underlying token
    function underlying() external view returns (address);

    /// @notice Collateral token mask of underlying token in the credit manager
    function tokenMask() external view returns (uint256);

    /// @notice Collateral token mask of eToken in the credit manager
    function eTokenMask() external view returns (uint256);

    /// @notice Deposit underlying tokens into Euler in exchange for eTokens
    /// @param amount Amount of underlying tokens to deposit, set to `type(uint256).max`
    ///        to deposit full amount (in this case, underlying will be disabled)
    /// @dev First param (`subAccountId`) is ignored since CAs can't use Euler's sub-accounts
    function deposit(uint256, uint256 amount) external;

    /// @notice Deposit all underlying tokens into Euler in exchange for eTokens, disables underlying
    function depositAll() external;

    /// @notice Withdraw underlying tokens from Euler and burn eTokens
    /// @param amount Amount of underlying tokens to withdraw, set to `type(uint256).max`
    ///        to withdraw full amount (in this case, EToken will be disabled)
    /// @dev First param (`subAccountId`) is ignored since CAs can't use Euler's sub-accounts
    function withdraw(uint256, uint256 amount) external;

    /// @notice Withdraw all underlying tokens from Euler and burn eTokens, disables EToken
    function withdrawAll() external;
}
