// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import { ArbitrumDomain } from "dss-test/domains/ArbitrumDomain.sol";

import "./IntegrationBase.t.sol";

import { ArbitrumDomainHost } from "../../domains/arbitrum/ArbitrumDomainHost.sol";
import { ArbitrumDomainGuest } from "../../domains/arbitrum/ArbitrumDomainGuest.sol";

abstract contract ArbitrumIntegrationTest is IntegrationBaseTest {

    function deployHost(address guestAddr) internal virtual override returns (BridgeInstance memory) {
        return DssBridge.deployArbitrumHost(
            address(this),
            hostDomain.readConfigAddress("admin"),
            guestDomain.readConfigBytes32("ilk"),
            address(dss.daiJoin),
            guestDomain.readConfigAddress("escrow"),
            address(teleport.router),
            address(ArbitrumDomain(address(guestDomain)).inbox()),
            guestAddr
        );
    }

    function deployGuest(
        DssInstance memory dss,
        address hostAddr
    ) internal virtual override returns (BridgeInstance memory) {
        return DssBridge.deployArbitrumGuest(
            address(this),
            guestDomain.readConfigAddress("admin"),
            address(dss.daiJoin),
            address(claimToken),
            address(rteleport.router),
            address(ArbitrumDomain(address(guestDomain)).arbSys()),
            hostAddr
        );
    }

    function initHost() internal virtual override {
        ArbitrumDomainHost _host = ArbitrumDomainHost(address(host));
        _host.file("glLift", 1_000_000);
        _host.file("glRectify", 1_000_000);
        _host.file("glCage", 1_000_000);
        _host.file("glExit", 1_000_000);
        _host.file("glDeposit", 1_000_000);
        _host.file("glInitializeRegisterMint", 1_000_000);
        _host.file("glInitializeSettle", 1_000_000);
    }

    function initGuest() internal virtual override {
    }

    function hostLift(uint256 wad) internal virtual override {
        ArbitrumDomainHost(address(host)).lift{value:1 ether}(wad, 1 ether, 0);
    }

    function hostRectify() internal virtual override {
        ArbitrumDomainHost(address(host)).rectify{value:1 ether}(1 ether, 0);
    }

    function hostCage() internal virtual override {
        ArbitrumDomainHost(address(host)).cage{value:1 ether}(1 ether, 0);
    }

    function hostExit(address usr, uint256 wad) internal virtual override {
        ArbitrumDomainHost(address(host)).exit{value:1 ether}(uint256(uint160(usr)), wad, 1 ether, 0);
    }

    function hostDeposit(address to, uint256 amount) internal virtual override {
        ArbitrumDomainHost(address(host)).deposit{value:1 ether}(to, amount, 1 ether, 0);
    }

    function hostInitializeRegisterMint(TeleportGUID memory teleport) internal virtual override {
        ArbitrumDomainHost(address(host)).initializeRegisterMint{value:1 ether}(teleport, 1 ether, 0);
    }

    function hostInitializeSettle(uint256 index) internal virtual override {
        ArbitrumDomainHost(address(host)).initializeSettle{value:1 ether}(index, 1 ether, 0);
    }

    function guestRelease() internal virtual override {
        ArbitrumDomainGuest(address(guest)).release();
    }

    function guestPush() internal virtual override {
        ArbitrumDomainGuest(address(guest)).push();
    }

    function guestTell() internal virtual override {
        ArbitrumDomainGuest(address(guest)).tell();
    }

    function guestWithdraw(address to, uint256 amount) internal virtual override {
        ArbitrumDomainGuest(address(guest)).withdraw(to, amount);
    }

    function guestInitializeRegisterMint(TeleportGUID memory teleport) internal virtual override {
        ArbitrumDomainGuest(address(guest)).initializeRegisterMint(teleport);
    }

    function guestInitializeSettle(uint256 index) internal virtual override {
        ArbitrumDomainGuest(address(guest)).initializeSettle(index);
    }

}

contract ArbitrumOneIntegrationTest is ArbitrumIntegrationTest {

    function setupGuestDomain() internal virtual override returns (BridgedDomain) {
        return new ArbitrumDomain(config, "arbitrum-one", hostDomain);
    }

}

contract ArbitrumNovaIntegrationTest is ArbitrumIntegrationTest {

    function setupGuestDomain() internal virtual override returns (BridgedDomain) {
        return new ArbitrumDomain(config, "arbitrum-nova", hostDomain);
    }

}
