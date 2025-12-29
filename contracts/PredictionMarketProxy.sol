// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionMarketProxy
 * @notice Minimal ERC1967 Proxy for PredictionMarketV1 UUPS upgradeable contract
 * @dev Deploy this with the implementation address and initialization data
 */
contract PredictionMarketProxy {
    // ERC1967 implementation slot
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    /**
     * @dev Initializes the proxy with an implementation contract
     * @param implementation Address of the implementation contract
     * @param _data Initialization calldata (call to initialize function)
     */
    constructor(address implementation, bytes memory _data) payable {
        require(implementation.code.length > 0, "ERC1967: implementation is not a contract");
        
        // Store implementation address
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        
        // Initialize if data provided
        if (_data.length > 0) {
            (bool success, bytes memory returndata) = implementation.delegatecall(_data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                } else {
                    revert("ERC1967: initialization failed");
                }
            }
        }
    }
    
    /**
     * @dev Fallback function that delegates calls to the implementation
     */
    fallback() external payable {
        address implementation;
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
        
        assembly {
            // Copy calldata to memory
            calldatacopy(0, 0, calldatasize())
            
            // Delegatecall to implementation
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            
            // Copy return data
            returndatacopy(0, 0, returndatasize())
            
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
    
    receive() external payable {}
}
