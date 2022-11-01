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

    function run() external {
        config = readInput("teleport");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        vm.startBroadcast();
        DssTeleport.deploy(
            msg.sender,
            config.readAddress(".admin"),
            config.readBytes32(".ilk"),
            config.readBytes32(".domain"),
            config.readBytes32(".parentDomain"),
            address(dss.daiJoin)
        );
        vm.stopBroadcast();
    }

}
