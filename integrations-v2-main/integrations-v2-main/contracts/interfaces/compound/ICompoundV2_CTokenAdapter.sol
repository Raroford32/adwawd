// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2023
pragma solidity ^0.8.17;

import {IAdapter} from "@gearbox-protocol/core-v2/contracts/interfaces/adapters/IAdapter.sol";

/// @notice When cToken operation produces an error
error CTokenError(uint256 errorCode);

/// @title Compound V2 cToken adapter interface
/// @notice Implements logic allowing CAs to interact with Compound's cTokens
interface ICompoundV2_CTokenAdapter is IAdapter {
    /// @notice cToken that this adapter is connected to
    function cToken() external view returns (address);

    /// @notice cToken's underlying token
    function underlying() external view returns (address);

    /// @notice Collateral token mask of underlying token in the credit manager
    function tokenMask() external view returns (uint256);

    /// @notice Collateral token mask of cToken in the credit manager
    function cTokenMask() external view returns (uint256);

    /// @notice Deposit given amount of underlying tokens into Compound in exchange for cTokens
    /// @param amount Amount of underlying tokens to deposit
    function mint(uint256 amount) external;

    /// @notice Deposit all underlying tokens into Compound in exchange for cTokens, disables underlying
    function mintAll() external;

    /// @notice Burn given amount of cTokens to withdraw underlying from Compound
    /// @param amount Amount of cTokens to burn
    function redeem(uint256 amount) external;

    /// @notice Withdraw all underlying tokens from Compound and burn cTokens, disables cToken
    function redeemAll() external;

    /// @notice Burn cTokens to withdraw given amount of underlying from Compound
    /// @param amount Amount of underlying to withdraw
    function redeemUnderlying(uint256 amount) external;
}
