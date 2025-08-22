// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/// @title Random Number Generator
/// @notice Provides pseudo-random number generation for testing scenarios
/// @dev Uses block properties and internal state for randomness generation

abstract contract Random {
    uint256 private seed;
    uint256 private nonce;
    
    /// @notice Set the random seed for deterministic testing
    /// @param _seed Initial seed value
    function setSeed(uint256 _seed) internal {
        seed = _seed;
        nonce = 0;
    }
    
    /// @notice Generate a random number in the range [0, max)
    /// @param max Maximum value (exclusive)
    /// @return Random number in range [0, max)
    function getRandomInRange(uint256 max) internal returns (uint256) {
        if (max == 0) return 0;
        
        nonce++;
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(
            seed,
            nonce,
            block.timestamp,
            block.difficulty,
            block.number
        )));
        
        return randomNumber % max;
    }
    
    /// @notice Generate a random number in range [0, max) with 95% bias toward max
    /// @param max Maximum value (exclusive)
    /// @return Random number biased toward maximum
    function getRandomInRange95(uint256 max) internal returns (uint256) {
        if (max == 0) return 0;
        
        uint256 random = getRandomInRange(max);
        
        // 95% bias toward maximum value
        if (getRandomInRange(100) < 95) {
            return (random * 95 + max * 5) / 100;
        }
        
        return random;
    }
    
    /// @notice Generate a random boolean value
    /// @return Random boolean
    function getRandomBool() internal returns (bool) {
        return getRandomInRange(2) == 1;
    }
    
    /// @notice Generate random bytes32
    /// @return Random bytes32 value
    function getRandomBytes32() internal returns (bytes32) {
        nonce++;
        return keccak256(abi.encodePacked(
            seed,
            nonce,
            block.timestamp,
            block.difficulty
        ));
    }
}