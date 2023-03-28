// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "dss-test/domains/Domain.sol";
import { ScriptTools } from "dss-test/ScriptTools.sol";
import { ClaimToken } from "xdomain-dss/ClaimToken.sol";

import { XDomainDss, DssInstance } from "../src/deploy/XDomainDss.sol";
import { DssTeleport, TeleportInstance } from "../src/deploy/DssTeleport.sol";
import { DssBridge, BridgeInstance } from "../src/deploy/DssBridge.sol";

// To deploy on a domain with an existing DAI + Token Bridge
contract DeployExistingTokenBridge is Script {

    using ScriptTools for string;

    string config;

    Domain hostDomain;
    address hostAdmin;

    Domain guestDomain;
    address guestAdmin;
    string guestType;

    string constant OPTIMISM = "optimism";
    string constant ARBITRUM = "arbitrum";

    function run() external {
        config = ScriptTools.loadConfig("config");

        hostDomain = new Domain(config, getChain(vm.envString("DEPLOY_HOST")));
        hostAdmin = hostDomain.readConfigAddress("admin");
        
        guestDomain = new Domain(config, getChain(vm.envString("DEPLOY_GUEST")));
        guestAdmin = guestDomain.readConfigAddress("admin");
        guestType = guestDomain.readConfigString("type");

        guestDomain.selectFork();
        address guestAddr = computeCreateAddress(msg.sender, vm.getNonce(msg.sender) + 36);
        address hostAddr;

        // Host domain deploy
        hostDomain.selectFork();

        vm.startBroadcast();
        if (guestType.eq(OPTIMISM)) {
            BridgeInstance memory bridge = DssBridge.deployOptimismHost(
                msg.sender,
                hostAdmin,
                guestDomain.readConfigBytes32FromString("ilk"),
                hostDomain.readConfigAddress("daiJoin"),
                guestDomain.readConfigAddress("escrow"),
                vm.envAddress("DEPLOY_ROUTER"),
                guestDomain.readConfigAddress("l1Messenger"),
                guestAddr
            );
            hostAddr = address(bridge.host);
        } else if (guestType.eq(ARBITRUM)) {
            BridgeInstance memory bridge = DssBridge.deployArbitrumHost(
                msg.sender,
                hostAdmin,
                guestDomain.readConfigBytes32FromString("ilk"),
                hostDomain.readConfigAddress("daiJoin"),
                guestDomain.readConfigAddress("escrow"),
                vm.envAddress("DEPLOY_ROUTER"),
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
        ClaimToken claimToken = new ClaimToken();       // TODO move this into DssInstance when settled
        claimToken.rely(guestAdmin);
        claimToken.deny(address(msg.sender));
        TeleportInstance memory teleport = DssTeleport.deploy(
            msg.sender,
            guestAdmin,
            guestDomain.readConfigBytes32FromString("teleportIlk"),
            guestDomain.readConfigBytes32FromString("domain"),
            hostDomain.readConfigBytes32FromString("domain"),
            address(dss.daiJoin)
        );
        if (guestType.eq(OPTIMISM)) {
            BridgeInstance memory bridge = DssBridge.deployOptimismGuest(
                msg.sender,
                guestAdmin,
                address(dss.daiJoin),
                address(claimToken),
                address(teleport.router),
                guestDomain.readConfigAddress("l2Messenger"),
                hostAddr
            );
            require(address(bridge.guest) == guestAddr, "Guest address mismatch");
        } else if (guestType.eq(ARBITRUM)) {
            BridgeInstance memory bridge = DssBridge.deployArbitrumGuest(
                msg.sender,
                guestAdmin,
                address(dss.daiJoin),
                address(claimToken),
                address(teleport.router),
                guestDomain.readConfigAddress("arbSys"),
                hostAddr
            );
            require(address(bridge.guest) == guestAddr, "Guest address mismatch");
        } else {
            revert("Unknown guest type");
        }
        vm.stopBroadcast();
    }

}
