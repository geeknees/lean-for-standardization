// ABOUTME: Initializes proxy ownership before the pinned registries' version-2 initialization.
// ABOUTME: Contains deployment plumbing only; registry behavior remains in the upstream sources.
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Hardhat emits artifacts for project contracts; this constructor preserves OZ's proxy behavior.
contract RegistryProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory initialization)
        ERC1967Proxy(implementation, initialization) {}
}

contract Bootstrap is OwnableUpgradeable, UUPSUpgradeable {
    // The Reputation and Validation implementations keep this address in slot zero.
    address private _identityRegistry;

    constructor() {
        _disableInitializers();
    }

    function initialize(address identityRegistry) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _identityRegistry = identityRegistry;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
