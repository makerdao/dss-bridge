// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";

import { DssTeleport } from "../src/deploy/DssTeleport.sol";

// Deploys an instance of dss-teleport onto an existing dss instance
contract DeployTeleportExistingDss is Script {

    using stdJson for string;
    using ScriptTools for string;

    string config;
    DssInstance dss;

    function run() external {
        config = ScriptTools.loadConfig("teleport");
        dss = MCD.loadFromChainlog(config.readAddress(".chainlog"));

        vm.startBroadcast();
        DssTeleport.deploy(
            msg.sender,
            config.readAddress(".admin"),
            config.readString(".ilk").stringToBytes32(),
            config.readString(".domain").stringToBytes32(),
            config.readString(".parentDomain").stringToBytes32(),
            address(dss.daiJoin)
        );
        vm.stopBroadcast();
    }

}
