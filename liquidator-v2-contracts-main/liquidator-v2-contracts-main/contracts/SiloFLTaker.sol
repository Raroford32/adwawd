pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISiloFlashLoan} from "./interfaces/ISiloFlashLoan.sol";

contract SiloFLTaker is Ownable {
    event SetAllowedFLReceiver(address indexed consumer, bool status);
    event SetTokenToSilo(address indexed token, address indexed silo);

    error CallerNotAllowedReceiverException();

    mapping(address => address) public tokenToSilo;
    mapping(address => bool) public allowedFLReceiver;

    modifier onlyAllowedFLReceiver() {
        if (!allowedFLReceiver[msg.sender]) revert CallerNotAllowedReceiverException();
        _;
    }

    function takeFlashLoan(address token, uint256 amount, bytes memory data) external onlyAllowedFLReceiver {
        ISiloFlashLoan(tokenToSilo[token]).flashLoan(msg.sender, token, amount, data);
    }

    function setAllowedFLReceiver(address receiver, bool status) external onlyOwner {
        if (allowedFLReceiver[receiver] == status) return;
        allowedFLReceiver[receiver] = status;
        emit SetAllowedFLReceiver(receiver, status);
    }

    function setTokenToSilo(address token, address silo) external onlyOwner {
        tokenToSilo[token] = silo;
        emit SetTokenToSilo(token, silo);
    }
}
