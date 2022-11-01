// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";

import { BridgeOracle } from "../BridgeOracle.sol";
import { ClaimToken } from "../ClaimToken.sol";
import { DomainHost } from "../DomainHost.sol";
import { DomainGuest } from "../DomainGuest.sol";

import { OptimismDomainHost } from "../domains/optimism/OptimismDomainHost.sol";
import { OptimismDomainGuest } from "../domains/optimism/OptimismDomainGuest.sol";
import { ArbitrumDomainHost } from "../domains/arbitrum/ArbitrumDomainHost.sol";
import { ArbitrumDomainGuest } from "../domains/arbitrum/ArbitrumDomainGuest.sol";

struct BridgeInstance {
    BridgeOracle oracle;
    ClaimToken claimToken;
    DomainGuest guest;
    DomainHost host;
}

interface EscrowLike {
    function approve(address, address, uint256) external;
}

struct DssBridgeHostConfig {
    address escrow;
    uint256 debtCeiling;
}

// Tools for deploying and setting up a dss-bridge instance
library DssBridge {

    function switchOwner(address base, address deployer, address newOwner) internal {
        WardsAbstract(base).rely(newOwner);
        WardsAbstract(base).deny(deployer);
    }

    function deployOptimismHost(
        address deployer,
        address owner,
        bytes32 ilk,
        address daiJoin,
        address escrow,
        address router,
        address l1Messenger,
        address guest
    ) internal returns (BridgeInstance memory bridge) {
        bridge.host = new OptimismDomainHost(
            ilk,
            daiJoin,
            escrow,
            router,
            l1Messenger,
            guest
        );
        bridge.oracle = new BridgeOracle(address(bridge.host));

        switchOwner(address(bridge.host), deployer, owner);
    }

    function deployOptimismGuest(
        address deployer,
        address owner,
        address daiJoin,
        address router,
        address l2Messenger,
        address host
    ) internal returns (BridgeInstance memory bridge) {
        bridge.claimToken = new ClaimToken();
        bridge.guest = new OptimismDomainGuest(
            daiJoin,
            address(bridge.claimToken),
            router,
            l2Messenger,
            host
        );

        switchOwner(address(bridge.guest), deployer, owner);
        switchOwner(address(bridge.claimToken), deployer, owner);
    }

    function deployArbitrumHost(
        address deployer,
        address owner,
        bytes32 ilk,
        address daiJoin,
        address escrow,
        address router,
        address inbox,
        address guest
    ) internal returns (BridgeInstance memory bridge) {
        bridge.host = new ArbitrumDomainHost(
            ilk,
            daiJoin,
            escrow,
            router,
            inbox,
            guest
        );
        bridge.oracle = new BridgeOracle(address(bridge.host));

        switchOwner(address(bridge.host), deployer, owner);
    }

    function deployArbitrumGuest(
        address deployer,
        address owner,
        address daiJoin,
        address router,
        address arbSys,
        address host
    ) internal returns (BridgeInstance memory bridge) {
        bridge.claimToken = new ClaimToken();
        bridge.guest = new ArbitrumDomainGuest(
            daiJoin,
            address(bridge.claimToken),
            router,
            arbSys,
            host
        );

        switchOwner(address(bridge.guest), deployer, owner);
        switchOwner(address(bridge.claimToken), deployer, owner);
    }

    function initHost(
        DssInstance memory dss,
        BridgeInstance memory bridge,
        DssBridgeHostConfig memory cfg
    ) internal {
        bytes32 ilk = bridge.host.ilk();
        bridge.host.file("vow", address(dss.vow));
        dss.vat.rely(address(bridge.host));
        EscrowLike(cfg.escrow).approve(address(dss.dai), address(bridge.host), type(uint256).max);
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.vat.rely(address(bridge.host));
        dss.spotter.file(ilk, "pip", address(bridge.oracle));
        dss.spotter.file(ilk, "mat", 10 ** 27);
        dss.spotter.poke(ilk);
        dss.vat.file(ilk, "line", cfg.debtCeiling);
        dss.vat.file("Line", dss.vat.Line() + cfg.debtCeiling);
        dss.cure.lift(address(bridge.host));
    }

    function initGuest(
        DssInstance memory dss,
        BridgeInstance memory bridge
    ) internal {
        bridge.claimToken.rely(address(bridge.guest));
        dss.end.file("claim", address(bridge.claimToken));
        dss.end.file("vow", address(bridge.guest));
        bridge.guest.file("end", address(dss.end));
        bridge.guest.rely(address(dss.end));
        dss.vat.rely(address(bridge.guest));
        dss.end.rely(address(bridge.guest));
    }

}
