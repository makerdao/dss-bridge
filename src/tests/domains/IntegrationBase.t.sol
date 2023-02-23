// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "dss-test/DssTest.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";

import { DaiAbstract, EndAbstract } from "dss-interfaces/Interfaces.sol";
import { Domain } from "dss-test/domains/Domain.sol";
import { RootDomain } from "dss-test/domains/RootDomain.sol";
import { BridgedDomain } from "dss-test/domains/BridgedDomain.sol";
import { ClaimToken } from "xdomain-dss/ClaimToken.sol";
import { Dai } from "xdomain-dss/Dai.sol";
import { DaiJoin } from "xdomain-dss/DaiJoin.sol";
import { End } from "xdomain-dss/End.sol";
import { Pot } from "xdomain-dss/Pot.sol";
import { Jug } from "xdomain-dss/Jug.sol";
import { Spotter } from "xdomain-dss/Spotter.sol";
import { Vat } from "xdomain-dss/Vat.sol";

import { DomainHost, TeleportGUID } from "../../DomainHost.sol";
import { DomainGuest } from "../../DomainGuest.sol";

import { XDomainDss, DssInstance, XDomainDssConfig } from "../../deploy/XDomainDss.sol";
import {
    DssTeleport,
    TeleportInstance,
    DssTeleportConfig,
    DssTeleportDomainConfig,
    TeleportRouter,
    TeleportFees
} from "../../deploy/DssTeleport.sol";
import { DssBridge, BridgeInstance, DssBridgeHostConfig } from "../../deploy/DssBridge.sol";

// TODO use actual dog when ready
contract DogMock {
    function wards(address) external pure returns (uint256) {
        return 1;
    }
    function file(bytes32,address) external {
        // Do nothing
    }
}

abstract contract IntegrationBaseTest is DssTest {

    using GodMode for *;
    using MCD for DssInstance;
    using stdJson for string;

    string config;
    Domain hostDomain;
    BridgedDomain guestDomain;

    // Host-side contracts
    DssInstance dss;
    TeleportInstance teleport;
    BridgeInstance bridge;
    DomainHost host;
    bytes32 ilk;
    bytes32 domain;
    address escrow;
    address admin;

    // Guest-side contracts
    DssInstance rdss;
    TeleportInstance rteleport;
    BridgeInstance rbridge;
    DomainGuest guest;
    ClaimToken claimToken;
    bytes32 rdomain;
    address radmin;

    bytes32 constant GUEST_COLL_ILK = "ETH-A";

    event FinalizeRegisterMint(TeleportGUID teleport);

    function setupGuestDomain() internal virtual returns (BridgedDomain);
    function deployHost(address guestAddr) internal virtual returns (BridgeInstance memory);
    function deployGuest(DssInstance memory dss, address hostAddr) internal virtual returns (BridgeInstance memory);
    function initHost() internal virtual;
    function initGuest() internal virtual;

    function setUp() public {
        config = ScriptTools.readInput("config");

        hostDomain = new RootDomain(config, getRelativeChain("mainnet"));
        hostDomain.selectFork();
        hostDomain.loadDssFromChainlog();
        dss = hostDomain.dss(); // For ease of access

        guestDomain = setupGuestDomain();

        domain = hostDomain.readConfigBytes32FromString("domain");
        rdomain = guestDomain.readConfigBytes32FromString("domain");
        admin = hostDomain.readConfigAddress("admin");
        radmin = guestDomain.readConfigAddress("admin");

        // Deploy all contracts
        teleport = DssTeleport.deploy(
            address(this),
            admin,
            hostDomain.readConfigBytes32FromString("teleportIlk"),
            domain,
            hostDomain.readConfigBytes32FromString("teleportParentDomain"),
            address(dss.daiJoin)
        );
        TeleportFees fees = DssTeleport.deployLinearFee(WAD / 10000, 8 days);
        address guestAddr = computeCreateAddress(address(this), 21);
        bridge = deployHost(guestAddr);
        host = bridge.host;
        escrow = guestDomain.readConfigAddress("escrow");
        ilk = host.ilk();

        guestDomain.selectFork();
        rdss = XDomainDss.deploy(
            address(this),
            radmin,
            guestDomain.readConfigAddress("dai")
        );
        claimToken = new ClaimToken();       // TODO move this into DssInstance when settled
        claimToken.rely(radmin);
        claimToken.deny(address(this));
        rteleport = DssTeleport.deploy(
            address(this),
            radmin,
            guestDomain.readConfigBytes32FromString("teleportIlk"),
            rdomain,
            guestDomain.readConfigBytes32FromString("teleportParentDomain"),
            address(rdss.daiJoin)
        );
        TeleportFees rfees = DssTeleport.deployLinearFee(WAD / 10000, 8 days);
        rbridge = deployGuest(rdss, address(bridge.host));
        guest = rbridge.guest;
        assertEq(address(guest), guestAddr, "guest address mismatch");

        // Mimic the spells (Host + Guest)
        hostDomain.selectFork();
        vm.startPrank(admin);
        DssTeleport.init(
            dss,
            teleport,
            DssTeleportConfig({
                debtCeiling: 2_000_000 * RAD,
                oracleThreshold: 13,
                oracleSigners: new address[](0)
            })
        );
        DssTeleport.initDomain(
            teleport,
            DssTeleportDomainConfig({
                domain: rdomain,
                fees: address(fees),
                gateway: address(host),
                debtCeiling: 1_000_000 * WAD
            })
        );
        DssBridge.initHost(
            dss,
            bridge,
            DssBridgeHostConfig({
                escrow: guestDomain.readConfigAddress("escrow"),
                debtCeiling: 1_000_000 * RAD
            })
        );
        initHost();
        vm.stopPrank();

        guestDomain.selectFork();
        vm.startPrank(radmin);
        XDomainDss.init(rdss, XDomainDssConfig({
            claimToken: address(claimToken),
            endWait: 1 hours
        }));
        DssTeleport.init(
            rdss,
            rteleport,
            DssTeleportConfig({
                debtCeiling: 2_000_000 * RAD,
                oracleThreshold: 13,
                oracleSigners: new address[](0)
            })
        );
        DssTeleport.initDomain(
            rteleport,
            DssTeleportDomainConfig({
                domain: domain,
                fees: address(rfees),
                gateway: address(guest),
                debtCeiling: 1_000_000 * WAD
            })
        );
        DssBridge.initGuest(
            rdss,
            rbridge
        );
        initGuest();
        vm.stopPrank();

        // Set up rdss and give auth for convenience
        rdss.giveAdminAccess(address(this));
        address(guest).setWard(address(this), 1);

        // Default back to host domain and give auth for convenience
        hostDomain.selectFork();
        dss.giveAdminAccess(address(this));
        address(host).setWard(address(this), 1);
    }

    function hostLift(uint256 wad) internal virtual;
    function hostRectify() internal virtual;
    function hostCage() internal virtual;
    function hostExit(address usr, uint256 wad) internal virtual;
    function hostDeposit(address to, uint256 amount) internal virtual;
    function hostInitializeRegisterMint(TeleportGUID memory teleport) internal virtual;
    function hostInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal virtual;
    function guestSurplus() internal virtual;
    function guestDeficit() internal virtual;
    function guestTell() internal virtual;
    function guestWithdraw(address to, uint256 amount) internal virtual;
    function guestInitializeRegisterMint(TeleportGUID memory teleport) internal virtual;
    function guestInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal virtual;

    function testRaiseDebtCeiling() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        (uint256 ink, uint256 art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(host.grain(), 0);
        assertEq(host.line(), 0);

        hostLift(100 ether);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(host.grain(), 100 ether);
        assertEq(host.line(), 100 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);

        // Play the message on L2
        guestDomain.relayFromHost(true);

        assertEq(rdss.vat.Line(), 100 * RAD);
    }

    function testRaiseLowerDebtCeiling() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        (uint256 ink, uint256 art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(host.grain(), 0);
        assertEq(host.line(), 0);

        hostLift(100 ether);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(host.grain(), 100 ether);
        assertEq(host.line(), 100 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);

        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.Line(), 100 * RAD);
        assertEq(rdss.vat.debt(), 0);

        // Pre-mint DAI is not released here
        hostDomain.selectFork();
        hostLift(50 ether);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(host.grain(), 100 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);

        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.Line(), 50 * RAD);
        assertEq(rdss.vat.debt(), 0);

        hostDomain.selectFork();
        host.release(50 ether);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);
        assertEq(host.grain(), 50 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 50 ether);

        // Add some debt to the guest instance, lower the DC and release some more pre-mint
        // This can only release pre-mint DAI up to the debt
        guestDomain.selectFork();
        rdss.vat.suck(address(guest), address(this), 40 * RAD);
        assertEq(rdss.vat.Line(), 50 * RAD);
        assertEq(rdss.vat.debt(), 40 * RAD);

        hostDomain.selectFork();
        hostLift(25 ether);
        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.Line(), 25 * RAD);
        assertEq(rdss.vat.debt(), 40 * RAD);
    }

    function testPushSurplus() public {
        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 vowSin = dss.vat.sin(address(dss.vow));
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        hostDomain.selectFork();

        assertEq(host.ddai(), 0);

        // Set global DC and add 50 DAI surplus + 20 DAI debt to vow
        hostLift(100 ether);
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        guestDomain.relayFromHost(true);
        rdss.vat.suck(address(123), address(guest), 50 * RAD);
        rdss.vat.suck(address(guest), address(123), 20 * RAD);

        assertEq(rdss.vat.dai(address(guest)), 50 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 20 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);

        guestSurplus();
        assertEq(rdss.vat.dai(address(guest)), 20 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 20 * RAD);
        guest.heal();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(rdss.vat.sin(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf - int256(30 * RAD));
        guestDomain.relayToHost(true);

        assertEq(dss.vat.dai(address(dss.vow)), vowDai);
        assertEq(dss.vat.sin(address(dss.vow)), vowSin);
        assertEq(dss.dai.balanceOf(escrow), escrowDai);

        assertEq(host.ddai(), 30 ether);

        host.accrue(0);

        assertEq(dss.vat.dai(address(dss.vow)), vowDai + 30 * RAD);
        assertEq(dss.vat.sin(address(dss.vow)), vowSin);
        assertEq(dss.dai.balanceOf(escrow), escrowDai - 30 ether);
    }

    function testPushDeficit() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 vowSin = dss.vat.sin(address(dss.vow));
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        hostDomain.selectFork();

        // Set global DC and add 20 DAI surplus + 50 DAI debt to vow
        hostLift(100 ether);
        guestDomain.relayFromHost(true);
        
        rdss.vat.suck(address(123), address(guest), 20 * RAD);
        rdss.vat.suck(address(guest), address(123), 50 * RAD);

        assertEq(rdss.vat.dai(address(guest)), 20 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);

        guestDeficit();
        guestDomain.relayToHost(true);

        guestDomain.selectFork();
        assertEq(rdss.vat.dai(address(guest)), 20 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        guest.heal();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(rdss.vat.sin(address(guest)), 30 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);
        hostDomain.selectFork();

        hostRectify();
        assertEq(dss.vat.dai(address(dss.vow)), vowDai);
        assertEq(dss.vat.sin(address(dss.vow)), vowSin + 30 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 130 ether);
        guestDomain.relayFromHost(true);

        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(30 * RAD));
        assertEq(rdss.vat.dai(address(guest)), 30 * RAD);

        guest.heal();

        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(rdss.vat.sin(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(30 * RAD));
    }

    function testGlobalShutdown() public {
        assertEq(host.live(), 1);
        assertEq(dss.vat.live(), 1);

        // Set up some debt in the guest instance
        hostLift(100 ether);
        guestDomain.relayFromHost(true);
        rdss.initIlk(GUEST_COLL_ILK);
        rdss.vat.file(GUEST_COLL_ILK, "line", 1_000_000 * RAD);
        rdss.vat.slip(GUEST_COLL_ILK, address(this), 40 ether);
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), 40 ether, 40 ether);

        assertEq(guest.live(), 1);
        assertEq(rdss.vat.live(), 1);
        assertEq(rdss.vat.debt(), 40 * RAD);
        (uint256 ink, uint256 art) = rdss.vat.urns(GUEST_COLL_ILK, address(this));
        assertEq(ink, 40 ether);
        assertEq(art, 40 ether);

        hostDomain.selectFork();
        dss.end.cage();
        host.deny(address(this));       // Confirm cage can be done permissionlessly
        hostCage();

        uint256 initialVatDai = dss.vat.dai(address(dss.vow));
        assertEq(dss.vat.live(), 0);
        assertEq(host.live(), 0);
        guestDomain.relayFromHost(true);
        assertEq(guest.live(), 0);
        assertEq(rdss.vat.live(), 0);
        assertEq(rdss.vat.debt(), 40 * RAD);
        (ink, art) = rdss.vat.urns(GUEST_COLL_ILK, address(this));
        assertEq(ink, 40 ether);
        assertEq(art, 40 ether);
        assertEq(rdss.vat.gem(GUEST_COLL_ILK, address(rdss.end)), 0);
        assertEq(rdss.vat.sin(address(guest)), 0);

        // --- Settle out the Guest instance ---

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));

        (ink, art) = rdss.vat.urns(GUEST_COLL_ILK, address(this));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(rdss.vat.gem(GUEST_COLL_ILK, address(rdss.end)), 40 ether);
        assertEq(rdss.vat.sin(address(guest)), 40 * RAD);

        vm.warp(block.timestamp + rdss.end.wait());

        rdss.end.thaw();
        guestTell();
        rdss.end.flow(GUEST_COLL_ILK);
        guestDomain.relayToHost(true);

        assertEq(dss.vat.dai(address(dss.vow)), initialVatDai + 60 * RAD); // 60 pre-mint dai is unused and returned as surplus

        // --- Settle out the Host instance ---

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(dss.vat.gem(ilk, address(dss.end)), 0);
        uint256 vowSin = dss.vat.sin(address(dss.vow));

        dss.end.cage(ilk);

        assertEq(dss.end.tag(ilk), RAY);
        assertEq(dss.end.gap(ilk), 0);

        dss.end.skim(ilk, address(host));

        assertEq(dss.end.gap(ilk), 0);
        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(dss.vat.gem(ilk, address(dss.end)), 100 ether);
        assertEq(dss.vat.sin(address(dss.vow)), vowSin + 100 * RAD);

        vm.warp(block.timestamp + dss.end.wait());

        // Clear out any surplus if it exists
        uint256 vowDai = dss.vat.dai(address(dss.vow));
        dss.vat.suck(address(dss.vow), address(123), vowDai);
        dss.vow.heal(vowDai);
        
        // Check debt is deducted properly
        uint256 debt = dss.vat.debt();
        dss.end.thaw();

        assertEq(dss.end.debt(), debt);

        dss.end.flow(ilk);

        // --- Do user redemption for guest domain collateral ---

        // Pretend you own 50% of all outstanding debt (should be a pro-rate claim on $20 for the guest domain)
        uint256 myDai = (dss.end.debt() / 2) / RAY;
        dss.vat.suck(address(123), address(this), myDai * RAY);
        dss.vat.hope(address(dss.end));

        // Pack all your DAI
        assertEq(dss.end.bag(address(this)), 0);
        dss.end.pack(myDai);
        assertEq(dss.end.bag(address(this)), myDai);

        // Should get 50 gems
        assertEq(dss.vat.gem(ilk, address(this)), 0);
        dss.end.cash(ilk, myDai);
        uint256 gems = dss.vat.gem(ilk, address(this));
        assertApproxEqRel(gems, 50 ether, WAD / 10000);

        // Exit to the guest domain
        hostExit(address(this), gems);
        assertEq(dss.vat.gem(ilk, address(this)), 0);
        guestDomain.relayFromHost(true);
        uint256 tokens = claimToken.balanceOf(address(this)) / RAY;
        assertApproxEqAbs(tokens, 20 * WAD, WAD / 10000);

        // Can now get some collateral on the guest domain
        claimToken.approve(address(rdss.end), type(uint256).max);
        assertEq(rdss.end.bag(address(this)), 0);
        rdss.end.pack(tokens);
        assertEq(rdss.end.bag(address(this)), tokens);

        // Should get some of the dummy collateral gems
        assertEq(rdss.vat.gem(GUEST_COLL_ILK, address(this)), 0);
        rdss.end.cash(GUEST_COLL_ILK, tokens);
        assertEq(rdss.vat.gem(GUEST_COLL_ILK, address(this)), tokens);

        // We can now exit through gem join or other standard exit function
    }

    function testDeposit() public {
        dss.dai.mint(address(this), 100 ether);
        dss.dai.approve(address(host), 100 ether);
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        hostDomain.selectFork();

        hostDeposit(address(123), 100 ether);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);
        guestDomain.relayFromHost(true);

        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(100 * RAD));
        assertEq(rdss.dai.balanceOf(address(123)), 100 ether);
    }

    function testWithdraw() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        hostDomain.selectFork();

        dss.dai.mint(address(this), 100 ether);
        dss.dai.approve(address(host), 100 ether);
        hostDeposit(address(this), 100 ether);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);
        assertEq(dss.dai.balanceOf(address(123)), 0);
        guestDomain.relayFromHost(true);

        rdss.vat.hope(address(rdss.daiJoin));
        rdss.dai.approve(address(guest), 100 ether);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(100 * RAD));
        assertEq(rdss.dai.balanceOf(address(this)), 100 ether);

        guestWithdraw(address(123), 100 ether);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);
        assertEq(rdss.dai.balanceOf(address(this)), 0);
        guestDomain.relayToHost(true);
        assertEq(dss.dai.balanceOf(escrow), escrowDai);
        assertEq(dss.dai.balanceOf(address(123)), 100 ether);
    }

    function testRegisterMint() public {
        TeleportGUID memory teleportToGuest = TeleportGUID({
            sourceDomain: domain,
            targetDomain: rdomain,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });
        TeleportGUID memory teleportToHost = TeleportGUID({
            sourceDomain: rdomain,
            targetDomain: domain,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        // Host -> Guest
        host.registerMint(teleportToGuest);
        hostInitializeRegisterMint(teleportToGuest);
        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleportToGuest);
        guestDomain.relayFromHost(true);

        // Guest -> Host
        guest.registerMint(teleportToHost);
        guestInitializeRegisterMint(teleportToHost);
        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleportToHost);
        guestDomain.relayToHost(true);
    }

    function testSettle() public {
        // Host -> Guest
        dss.dai.mint(address(host), 100 ether);
        host.settle(domain, rdomain, 100 ether);
        hostInitializeSettle(domain, rdomain);
        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.dai(address(rteleport.join)), 100 * RAD);

        // Guest -> Host
        rdss.dai.setBalance(address(guest), 50 ether);
        guest.settle(rdomain, domain, 50 ether);
        guestInitializeSettle(rdomain, domain);
        guestDomain.relayToHost(true);
        assertEq(dss.vat.dai(address(teleport.join)), 50 * RAD);
    }

    function _setInitialCaseState(uint256 ink, uint256 art) internal returns (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) {
        // No dai or sin for vow (to simply asserts)
        vm.store(
            address(dss.vat),
            bytes32(uint256(keccak256(abi.encode(address(dss.vow), uint256(5))))),
            bytes32(uint256(0))
        );
        assertEq(dss.vat.dai(address(dss.vow)), 0);
        vm.store(
            address(dss.vat),
            bytes32(uint256(keccak256(abi.encode(address(dss.vow), uint256(6))))),
            bytes32(uint256(0))
        );
        assertEq(dss.vat.sin(address(dss.vow)), 0);
        vm.store(
            address(dss.vat),
            bytes32(uint256(8)),
            bytes32(uint256(0))
        );
        assertEq(dss.vat.vice(), 0);
        //

        existingVatDebt = dss.vat.debt();
        existingEscrowDai = dss.dai.balanceOf(address(escrow));
        hostDomain.selectFork();
        assertEq(host.grain(), 0);

        guestDomain.selectFork();
        assertEq(rdss.vat.Line(), 0);
        existingSurf = Vat(address(rdss.vat)).surf();
        assertEq(rdss.vat.debt(), 0);
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), 0);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)), 0);

        hostDomain.selectFork();
        dss.dai.mint(address(this), 20 ether);
        dss.dai.approve(address(host), 20 ether);
        hostDeposit(address(this), 20 ether);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 20 ether);
        guestDomain.relayFromHost(true);

        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(20 * RAD));

        hostDomain.selectFork();
        hostLift(100 ether);
        assertEq(dss.vat.debt(), existingVatDebt + 100 * RAD);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 120 ether);

        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.Line(), 100 * RAD);

        rdss.initIlk(GUEST_COLL_ILK);
        rdss.vat.file(GUEST_COLL_ILK, "line", 100 * RAD);
        rdss.vat.slip(GUEST_COLL_ILK, address(this), int256(ink));
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), int256(ink), int256(art));
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), ink);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), art * RAY);
        assertEq(rdss.vat.debt(), art * RAY);
    }

    function _checkFinalState(
        uint256 grain,
        uint256 l1Vatdebt,
        uint256 l1EscrowDai,
        uint256 l2EndDebt,
        uint256 l2EndFix,
        int256  l2Supply
    ) internal {
        uint256 activeFork = vm.activeFork();

        hostDomain.selectFork();
        dss.vow.heal(dss.vat.dai(address(dss.vow)));
        assertEq(dss.vat.debt(), l1Vatdebt, "Error final L1 debt");
        assertEq(dss.dai.balanceOf(address(escrow)), l1EscrowDai, "Error final L1 escrow dai");
        assertEq(host.grain(), grain, "Error final L1 grain");
        assertEq(dss.vat.gem(host.ilk(), address(dss.end)), grain, "Error final L1 end gem");

        guestDomain.selectFork();
        assertEq(rdss.end.debt(), l2EndDebt, "Error final L2 end debt");
        assertEq(rdss.end.fix(GUEST_COLL_ILK), l2EndFix, "Error final L2 end fix");
        assertEq(int256(rdss.vat.debt()) + Vat(address(rdss.vat)).surf() - int256(rdss.vat.dai(address(guest))), l2Supply, "Error final L2 supply");

        vm.selectFork(activeFork);
    }

    function testCaseNonSurplusOrDeficit() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      95 * RAD,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusAccounted() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.03 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 97.85 * 10**45);
        assertEq(rdss.vat.debt(), 97.85 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 2.85 * 10**45);
        //

        guestSurplus();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(17.15 * 10**45));

        guestDomain.relayToHost(true);
        assertEq(host.ddai(), 2.85 ether);

        host.accrue(97.85 ether);

        assertEq(dss.vat.dai(address(dss.vow)), 2.85 * 10**45);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 117.15 ether);

        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      97.85 * 10**45,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusNotAccounted() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.03 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 97.85 * 10**45);
        assertEq(rdss.vat.debt(), 97.85 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 2.85 * 10**45);
        //

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      95 * RAD,
            /*l2EndFix:*/       1.03 * 10**27,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusAccountedButNotAccrued() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.03 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 97.85 * 10**45);
        assertEq(rdss.vat.debt(), 97.85 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 2.85 * 10**45);
        //

        guestSurplus();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(17.15 * 10**45));

        guestDomain.relayToHost(true);
        assertEq(host.ddai(), 2.85 ether);

        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      97.85 * 10**45,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusMessageHalfWay() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.03 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 97.85 * 10**45);
        assertEq(rdss.vat.debt(), 97.85 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 2.85 * 10**45);
        //

        guestSurplus();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(17.15 * 10**45));

        hostDomain.selectFork();

        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true); // This will relay first the surplus message and then the tell message
        // TODO: Prove that the tell message can not be relayed before the surplus message if it was in queue

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      97.85 * 10**45,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusAccountedOverPreMinted() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.1 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 104.5 * 10**45);
        assertEq(rdss.vat.debt(), 104.5 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 9.5 * 10**45);
        //

        guestSurplus();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf + int256(10.5 * 10**45));

        guestDomain.relayToHost(true);
        assertEq(host.ddai(), 9.5 ether);

        host.accrue(104.5 ether);

        assertEq(dss.vat.dai(address(dss.vow)), 9.5 * 10**45);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 115 ether);
        assertEq(dss.vat.debt(), existingVatDebt + 104.5 * 10**45);

        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          104.5 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      104.5 * 10**45,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseSurplusNotAccountedOverPreMinted() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 95 ether);

        // Simulate fees were generated and collected in the local surplus buffer
        rdss.vat.fold(GUEST_COLL_ILK, address(guest), int256(0.1 * 10**27));
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 104.5 * 10**45);
        assertEq(rdss.vat.debt(), 104.5 * 10**45);
        assertEq(rdss.vat.dai(address(guest)), 9.5 * 10**45);
        //

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      95 * RAD,
            /*l2EndFix:*/       1.1 * 10**27,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
    }

    function testCaseDeficitRectified() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 50 ether);

        // Simulate the position is liquidated
        rdss.vat.grab(GUEST_COLL_ILK, address(this), address(0), address(guest), -int256(1000 ether), -int256(50 ether));

        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(rdss.vat.vice(), 50 * RAD);

        rdss.vat.slip(GUEST_COLL_ILK, address(this), 1000 ether);
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), 1000 ether, 45 ether);
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), 1000 ether);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 45 * RAD);
        assertEq(rdss.vat.debt(), 95 * RAD);

        guestDeficit();
        assertEq(guest.dsin(), 50 ether);

        guestDomain.relayToHost(true);

        assertEq(host.dsin(), 50 ether);

        hostRectify();

        assertEq(dss.vat.debt(), existingVatDebt + 150 * RAD);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 170 ether);
        assertEq(dss.vat.sin(address(dss.vow)), 50 * RAD);
        assertEq(dss.vat.vice(), 50 * RAD);
        assertEq(host.dsin(), 0);

        guestDomain.relayFromHost(true);

        guest.heal();

        assertEq(rdss.vat.debt(), 45 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 0);
        assertEq(rdss.vat.vice(), 0);
        assertEq(guest.dsin(), 0);

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        assertEq(rdss.end.debt(), 45 * RAD);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      45 * RAD,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
        assertEq(dss.vat.vice(), 95 * RAD);
    }

    function testCaseDeficitHalfWayRectified() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 50 ether);

        // Simulate the position is liquidated
        rdss.vat.grab(GUEST_COLL_ILK, address(this), address(0), address(guest), -int256(1000 ether), -int256(50 ether));

        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(rdss.vat.vice(), 50 * RAD);

        rdss.vat.slip(GUEST_COLL_ILK, address(this), 1000 ether);
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), 1000 ether, 45 ether);
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), 1000 ether);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 45 * RAD);
        assertEq(rdss.vat.debt(), 95 * RAD);

        guestDeficit();
        assertEq(guest.dsin(), 50 ether);

        guestDomain.relayToHost(true);

        assertEq(host.dsin(), 50 ether);

        hostRectify();

        assertEq(dss.vat.debt(), existingVatDebt + 150 * RAD);
        assertEq(dss.dai.balanceOf(address(escrow)), existingEscrowDai + 170 ether);
        assertEq(dss.vat.sin(address(dss.vow)), 50 * RAD);
        assertEq(dss.vat.vice(), 50 * RAD);
        assertEq(host.dsin(), 0);

        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);
        // TODO: We might want to prove that rectify message has to be received before cage one

        guest.heal();

        assertEq(rdss.vat.debt(), 45 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 0);
        assertEq(rdss.vat.vice(), 0);
        assertEq(guest.dsin(), 0);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        guest.heal();
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        assertEq(rdss.end.debt(), 45 * RAD);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      45 * RAD,
            /*l2EndFix:*/       1 * RAY,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
        assertEq(dss.vat.vice(), 95 * RAD);
    }

    function testCaseDeficitNonRectified() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 50 ether);

        // Simulate the position is liquidated
        rdss.vat.grab(GUEST_COLL_ILK, address(this), address(0), address(guest), -int256(1000 ether), -int256(50 ether));

        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(rdss.vat.vice(), 50 * RAD);

        rdss.vat.slip(GUEST_COLL_ILK, address(this), 1000 ether);
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), 1000 ether, 45 ether);
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), 1000 ether);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 45 * RAD);
        assertEq(rdss.vat.debt(), 95 * RAD);

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        assertEq(rdss.end.debt(), 95 * RAD);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      95 * RAD,
            /*l2EndFix:*/       45 * RAY / 95,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
        assertEq(dss.vat.vice(), 95 * RAD);
    }

    function testCaseDeficitHalfWayNonRectified() public {
        (uint256 existingVatDebt, uint256 existingEscrowDai, int256 existingSurf) = _setInitialCaseState(1000 ether, 50 ether);

        // Simulate the position is liquidated
        rdss.vat.grab(GUEST_COLL_ILK, address(this), address(0), address(guest), -int256(1000 ether), -int256(50 ether));

        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(rdss.vat.vice(), 50 * RAD);

        rdss.vat.slip(GUEST_COLL_ILK, address(this), 1000 ether);
        rdss.vat.frob(GUEST_COLL_ILK, address(this), address(this), address(this), 1000 ether, 45 ether);
        assertEq(Vat(address(rdss.vat)).ink(GUEST_COLL_ILK, address(this)), 1000 ether);
        assertEq(Vat(address(rdss.vat)).art(GUEST_COLL_ILK, address(this)) * Vat(address(rdss.vat)).rate(GUEST_COLL_ILK), 45 * RAD);
        assertEq(rdss.vat.debt(), 95 * RAD);

        guestDeficit();
        assertEq(guest.dsin(), 50 ether);

        hostDomain.selectFork();
        dss.end.cage();
        dss.end.cage(host.ilk());
        dss.end.skim(host.ilk(), address(host));

        hostCage();
        guestDomain.relayFromHost(true);

        rdss.end.cage(GUEST_COLL_ILK);
        rdss.end.skim(GUEST_COLL_ILK, address(this));
        vm.warp(block.timestamp + rdss.end.wait());
        rdss.end.thaw();
        rdss.end.flow(GUEST_COLL_ILK);

        assertEq(rdss.end.debt(), 95 * RAD);

        guestTell();
        guestDomain.relayToHost(true);

        _checkFinalState(
            /*grain:*/          100 ether,
            /*l1Vatdebt:*/      existingVatDebt + 95 * RAD,
            /*l1EscrowDai:*/    existingEscrowDai + 115 ether,
            /*l2EndDebt:*/      95 * RAD,
            /*l2EndFix:*/       45 * RAY / 95,
            /*l2Supply:*/       existingSurf + int256(115 * RAD)
        );
        assertEq(dss.vat.vice(), 95 * RAD);
    }
}
