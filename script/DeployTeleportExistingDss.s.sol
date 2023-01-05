// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";

import { DssTeleport } from "../src/deploy/DssTeleport.sol";

// Deploys an instance of dss-teleport onto an existing dss instance
contract DeployTeleportExistingDss is Script {

    using stdJson for string;

    string config;
    DssInstance dss;

    function readInput(string memory input) internal returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string.concat("/script/input/", vm.toString(block.chainid), "/");
        return vm.readFile(string.concat(root, chainInputFolder, string.concat(input, ".json")));
    }

    function bytesToBytes32(bytes memory b) private pure returns (bytes32) {
        bytes32 out;
        for (uint256 i = 0; i < b.length; i++) {
            out |= bytes32(b[i] & 0xFF) >> (i * 8);
        }
        return out;
    }

    function run() external {
        config = readInput("teleport");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        vm.startBroadcast();
        DssTeleport.deploy(
            msg.sender,
            config.readAddress(".admin"),
            bytesToBytes32(bytes(config.readString(".ilk"))),
            bytesToBytes32(bytes(config.readString(".domain"))),
            bytesToBytes32(bytes(config.readString(".parentDomain"))),
            address(dss.daiJoin)
        );
        vm.stopBroadcast();
    }

}
