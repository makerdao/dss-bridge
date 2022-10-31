// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

import "forge-std/Script.sol";
import "dss-test/domains/Domain.sol";

import { XDomainDss, DssInstance } from "../src/deploy/XDomainDss.sol";
import { DssBridge, BridgeInstance } from "../src/deploy/DssBridge.sol";

// To deploy on a domain with an existing DAI + Token Bridge
contract DeployExistingTokenBridge is Script {

    string config;

    Domain hostDomain;
    address hostAdmin;

    Domain guestDomain;
    address guestAdmin;
    bytes32 guestType;

    bytes32 constant OPTIMISM = keccak256(abi.encodePacked("optimism"));
    bytes32 constant ARBITRUM = keccak256(abi.encodePacked("arbitrum"));

    function readInput(string memory input) internal returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainInputFolder = string.concat("/script/input/", vm.toString(block.chainid), "/");
        return vm.readFile(string.concat(root, chainInputFolder, string.concat(input, ".json")));
    }

    function run() external {
        config = readInput("config");

        hostDomain = new Domain(config, vm.envString("DEPLOY_HOST"));
        hostAdmin = hostDomain.readConfigAddress("admin");
        
        guestDomain = new Domain(config, vm.envString("DEPLOY_GUEST"));
        guestAdmin = guestDomain.readConfigAddress("admin");
        guestType = keccak256(abi.encodePacked(guestDomain.readConfigString("type")));

        guestDomain.selectFork();
        address guestAddr = computeCreateAddress(address(msg.sender), vm.getNonce(address(msg.sender)) + 15);
        address hostAddr;

        // Host domain deploy
        hostDomain.selectFork();

        vm.startBroadcast();
        if (guestType == OPTIMISM) {
            BridgeInstance memory bridge = DssBridge.deployOptimismHost(
                msg.sender,
                hostAdmin,
                guestDomain.readConfigBytes32("ilk"),
                hostDomain.readConfigAddress("daiJoin"),
                guestDomain.readConfigAddress("escrow"),
                address(0),     // TODO router support
                guestDomain.readConfigAddress("l1Messenger"),
                guestAddr
            );
            hostAddr = address(bridge.host);
        } else if (guestType == ARBITRUM) {
            BridgeInstance memory bridge = DssBridge.deployArbitrumHost(
                msg.sender,
                hostAdmin,
                guestDomain.readConfigBytes32("ilk"),
                hostDomain.readConfigAddress("daiJoin"),
                guestDomain.readConfigAddress("escrow"),
                address(0),     // TODO router support
                guestDomain.readConfigAddress("inbox"),
                guestAddr
            );
            hostAddr = address(bridge.host);
        } else {
            revert("Unknown guest type");
        }
        vm.stopBroadcast();

        // Guest domain deploy
        guestDomain.selectFork();

        vm.startBroadcast();
        DssInstance memory dss = XDomainDss.deploy(
            msg.sender,
            guestAdmin,
            guestDomain.readConfigAddress("dai")
        );
        if (guestType == OPTIMISM) {
            BridgeInstance memory bridge = DssBridge.deployOptimismGuest(
                msg.sender,
                guestAdmin,
                guestDomain.readConfigBytes32("domain"),
                address(dss.daiJoin),
                address(0),     // TODO router support
                guestDomain.readConfigAddress("l2Messenger"),
                hostAddr
            );
            //require(address(bridge.guest) == guestAddr, "Guest address mismatch");
        } else if (guestType == ARBITRUM) {
            BridgeInstance memory bridge = DssBridge.deployOptimismGuest(
                msg.sender,
                guestAdmin,
                guestDomain.readConfigBytes32("domain"),
                address(dss.daiJoin),
                address(0),     // TODO router support
                guestDomain.readConfigAddress("arbSys"),
                hostAddr
            );
            //require(address(bridge.guest) == guestAddr, "Guest address mismatch");
        } else {
            revert("Unknown guest type");
        }
        vm.stopBroadcast();
    }

}
