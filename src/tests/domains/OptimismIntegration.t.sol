// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import { OptimismDomain } from "dss-test/domains/OptimismDomain.sol";

import "./IntegrationBase.t.sol";

import { OptimismDomainHost } from "../../domains/optimism/OptimismDomainHost.sol";
import { OptimismDomainGuest } from "../../domains/optimism/OptimismDomainGuest.sol";

contract OptimismIntegrationTest is IntegrationBaseTest {

    function setupGuestDomain() internal virtual override returns (BridgedDomain) {
        return new OptimismDomain(config, "optimism", hostDomain);
    }

    function deployHost(address guestAddr) internal virtual override returns (BridgeInstance memory) {
        return DssBridge.deployOptimismHost(
            address(this),
            hostDomain.readConfigAddress("admin"),
            guestDomain.readConfigBytes32("ilk"),
            address(dss.daiJoin),
            guestDomain.readConfigAddress("escrow"),
            address(teleport.router),
            address(OptimismDomain(address(guestDomain)).l1Messenger()),
            guestAddr
        );
    }

    function deployGuest(
        DssInstance memory dss,
        address hostAddr
    ) internal virtual override returns (BridgeInstance memory) {
        return DssBridge.deployOptimismGuest(
            address(this),
            guestDomain.readConfigAddress("admin"),
            address(dss.daiJoin),
            address(claimToken),
            address(rteleport.router),
            address(OptimismDomain(address(guestDomain)).l2Messenger()),
            hostAddr
        );
    }

    function initHost() internal virtual override {
        OptimismDomainHost _host = OptimismDomainHost(address(host));
        _host.file("glLift", 1_000_000);
        _host.file("glRectify", 1_000_000);
        _host.file("glCage", 1_000_000);
        _host.file("glExit", 1_000_000);
        _host.file("glDeposit", 1_000_000);
        _host.file("glInitializeRegisterMint", 1_000_000);
        _host.file("glInitializeSettle", 1_000_000);
    }

    function initGuest() internal virtual override {
        OptimismDomainGuest _guest = OptimismDomainGuest(address(guest));
        _guest.filegl("glRelease", 1_000_000);
        _guest.filegl("glPush", 1_000_000);
        _guest.filegl("glTell", 1_000_000);
        _guest.filegl("glWithdraw", 1_000_000);
        _guest.filegl("glFlush", 1_000_000);
        _guest.filegl("glInitializeRegisterMint", 1_000_000);
        _guest.filegl("glInitializeSettle", 1_000_000);
    }

    function hostLift(uint256 wad) internal virtual override {
        OptimismDomainHost(address(host)).lift(wad);
    }

    function hostRectify() internal virtual override {
        OptimismDomainHost(address(host)).rectify();
    }

    function hostCage() internal virtual override {
        OptimismDomainHost(address(host)).cage();
    }

    function hostExit(address usr, uint256 wad) internal virtual override {
        OptimismDomainHost(address(host)).exit(usr, wad);
    }

    function hostDeposit(address to, uint256 amount) internal virtual override {
        OptimismDomainHost(address(host)).deposit(to, amount);
    }

    function hostInitializeRegisterMint(TeleportGUID memory teleport) internal virtual override {
        OptimismDomainHost(address(host)).initializeRegisterMint(teleport);
    }

    function hostInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal virtual override {
        OptimismDomainGuest(address(host)).initializeSettle(sourceDomain, targetDomain);
    }

    function guestRelease() internal virtual override {
        OptimismDomainGuest(address(guest)).release();
    }

    function guestSurplus() internal virtual override {
        OptimismDomainGuest(address(guest)).surplus();
    }

    function guestDeficit() internal virtual override {
        OptimismDomainGuest(address(guest)).deficit();
    }

    function guestTell() internal virtual override {
        OptimismDomainGuest(address(guest)).tell();
    }

    function guestWithdraw(address to, uint256 amount) internal virtual override {
        OptimismDomainGuest(address(guest)).withdraw(to, amount);
    }

    function guestInitializeRegisterMint(TeleportGUID memory teleport) internal virtual override {
        OptimismDomainGuest(address(guest)).initializeRegisterMint(teleport);
    }

    function guestInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal virtual override {
        OptimismDomainGuest(address(guest)).initializeSettle(sourceDomain, targetDomain);
    }

}
