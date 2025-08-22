// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2022
pragma solidity ^0.8.10;

/**
 * @title TreasuryMock
 * @notice Just keeps money, used for test purpodes only
 * @author Gearbox
 */
contract TreasuryMock {
    // emits each time when money come
    event NewDonation(uint256 amount);

    receive() external payable {
        emit NewDonation(msg.value);
    }
}
