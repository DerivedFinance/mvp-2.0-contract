// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library StorageSlot {
    function getAddressAt(bytes32 slot) internal view returns (address a) {
        assembly {
            a := sload(slot)
        }
    }

    function setAddressAt(bytes32 slot, address address_) internal {
        assembly {
            sstore(slot, address_)
        }
    }
}

contract Proxy {
    address public callerAddress;
    address private owner;

    bytes32 private constant _IMPL_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    constructor() {
        owner = msg.sender;
    }

    function setImplementation(address implementation_) public onlyOwner {
        StorageSlot.setAddressAt(_IMPL_SLOT, implementation_);
    }

    function getImplementation() public view returns (address) {
        return StorageSlot.getAddressAt(_IMPL_SLOT);
    }

    function _delegate(address impl) internal virtual {
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())

            let result := delegatecall(gas(), impl, ptr, calldatasize(), 0, 0)

            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    fallback() external {
        callerAddress = msg.sender;
        _delegate(StorageSlot.getAddressAt(_IMPL_SLOT));
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Proxy: The caller is not the owner");
        _;
    }
}