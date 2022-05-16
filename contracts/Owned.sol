// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Owned {
    address public ownerAddress;
    address public nominatedOwner;

    constructor() {
        ownerAddress = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "You must be nominated before you can accept ownership");
        emit OwnerChanged(ownerAddress, nominatedOwner);
        ownerAddress = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(msg.sender == ownerAddress, "Only the contract owner may perform this action");
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}