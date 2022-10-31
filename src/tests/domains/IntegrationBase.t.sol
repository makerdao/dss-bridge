// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

import "dss-test/DSSTest.sol";
import "ds-value/value.sol";
import { MCD, DssInstance } from "dss-test/MCD.sol";

import { DaiAbstract, EndAbstract } from "dss-interfaces/Interfaces.sol";
import { BridgedDomain } from "dss-test/domains/BridgedDomain.sol";
import { RootDomain } from "dss-test/domains/RootDomain.sol";
import { Cure } from "xdomain-dss/Cure.sol";
import { Dai } from "xdomain-dss/Dai.sol";
import { DaiJoin } from "xdomain-dss/DaiJoin.sol";
import { End } from "xdomain-dss/End.sol";
import { Pot } from "xdomain-dss/Pot.sol";
import { Jug } from "xdomain-dss/Jug.sol";
import { Spotter } from "xdomain-dss/Spotter.sol";
import { Vat } from "xdomain-dss/Vat.sol";

import { ClaimToken } from "../../ClaimToken.sol";
import { DomainHost, TeleportGUID } from "../../DomainHost.sol";
import { DomainGuest } from "../../DomainGuest.sol";
import { BridgeOracle } from "../../BridgeOracle.sol";
import { RouterMock } from "../mocks/RouterMock.sol";

import { XDomainDss, DssInstance } from "../../deploy/XDomainDss.sol";
import { DssBridge, BridgeInstance } from "../../deploy/DssBridge.sol";

// TODO use actual dog when ready
contract DogMock {
    function wards(address) external pure returns (uint256) {
        return 1;
    }
    function file(bytes32,address) external {
        // Do nothing
    }
}

abstract contract IntegrationBaseTest is DSSTest {

    using GodMode for *;
    using MCD for DssInstance;

    string config;
    RootDomain rootDomain;
    BridgedDomain guestDomain;

    // Host-side contracts
    DssInstance dss;
    bytes32 ilk;
    address escrow;
    BridgeOracle pip;
    DomainHost host;
    RouterMock hostRouter;

    // Guest-side contracts
    DssInstance rdss;
    ClaimToken claimToken;
    DomainGuest guest;
    RouterMock guestRouter;

    bytes32 constant GUEST_COLL_ILK = "ETH-A";

    event FinalizeRegisterMint(TeleportGUID teleport);

    function setupEnv() internal virtual override {
        config = readInput("config");

        rootDomain = new RootDomain(config, "root");
        rootDomain.selectFork();
        rootDomain.loadDssFromChainlog();
        dss = rootDomain.dss(); // For ease of access
    }

    function setupGuestDomain() internal virtual returns (BridgedDomain);
    function deployHost(address guestAddr) internal virtual returns (BridgeInstance memory);
    function deployGuest(DssInstance memory dss, address hostAddr) internal virtual returns (BridgeInstance memory);
    function initHost() internal virtual;
    function initGuest() internal virtual;

    function postSetup() internal virtual override {
        guestDomain = setupGuestDomain();

        // Deploy all contracts
        hostRouter = new RouterMock(address(dss.dai));
        address guestAddr = computeCreateAddress(address(this), 15);
        BridgeInstance memory hostBridge = deployHost(guestAddr);
        host = hostBridge.host;
        escrow = guestDomain.readConfigAddress("escrow");
        pip = hostBridge.oracle;
        ilk = host.ilk();

        guestDomain.selectFork();
        rdss = XDomainDss.deploy(
            address(this),
            guestDomain.readConfigAddress("admin"),
            guestDomain.readConfigAddress("dai")
        );
        guestRouter = new RouterMock(address(rdss.dai));
        BridgeInstance memory guestBridge = deployGuest(rdss, address(hostBridge.host));
        guest = guestBridge.guest;
        assertEq(address(guest), guestAddr, "guest address mismatch");
        claimToken = guestBridge.claimToken;

        // Mimic the spells (Host + Guest)
        rootDomain.selectFork();
        vm.startPrank(rootDomain.readConfigAddress("admin"));
        DssBridge.initHost(
            dss,
            hostBridge,
            guestDomain.readConfigAddress("escrow"),
            1_000_000 * RAD
        );
        initHost();
        vm.stopPrank();

        guestDomain.selectFork();
        vm.startPrank(guestDomain.readConfigAddress("admin"));
        XDomainDss.init(rdss, 1 hours);
        DssBridge.initGuest(
            rdss,
            guestBridge
        );
        initGuest();
        vm.stopPrank();

        // Set up rdss and give auth for convenience
        rdss.giveAdminAccess(address(this));
        address(guest).setWard(address(this), 1);

        // Default back to host domain and give auth for convenience
        rootDomain.selectFork();
        dss.giveAdminAccess(address(this));
        address(host).setWard(address(this), 1);
    }

    function hostLift(uint256 wad) internal virtual;
    function hostRectify() internal virtual;
    function hostCage() internal virtual;
    function hostExit(address usr, uint256 wad) internal virtual;
    function hostDeposit(address to, uint256 amount) internal virtual;
    function hostInitializeRegisterMint(TeleportGUID memory teleport) internal virtual;
    function hostInitializeSettle(uint256 index) internal virtual;
    function guestRelease() internal virtual;
    function guestPush() internal virtual;
    function guestTell() internal virtual;
    function guestWithdraw(address to, uint256 amount) internal virtual;
    function guestInitializeRegisterMint(TeleportGUID memory teleport) internal virtual;
    function guestInitializeSettle(uint256 index) internal virtual;

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

        // Pre-mint DAI is not released here
        rootDomain.selectFork();
        hostLift(50 ether);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(host.grain(), 100 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 100 ether);

        guestDomain.relayFromHost(true);
        assertEq(rdss.vat.Line(), 50 * RAD);

        // Notify the host that the DAI is safe to remove
        guestRelease();

        assertEq(rdss.vat.Line(), 50 * RAD);
        assertEq(rdss.vat.debt(), 0);

        guestDomain.relayToHost(true);
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

        rootDomain.selectFork();
        hostLift(25 ether);
        guestDomain.relayFromHost(true);
        guestRelease();
        guestDomain.relayToHost(true);

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 40 ether);
        assertEq(art, 40 ether);
        assertEq(host.grain(), 40 ether);
        assertEq(host.line(), 25 * RAD);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 40 ether);
    }

    function testPushSurplus() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 vowSin = dss.vat.sin(address(dss.vow));
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        rootDomain.selectFork();

        // Set global DC and add 50 DAI surplus + 20 DAI debt to vow
        hostLift(100 ether);
        guestDomain.relayFromHost(true);
        rdss.vat.suck(address(123), address(guest), 50 * RAD);
        rdss.vat.suck(address(guest), address(123), 20 * RAD);

        assertEq(rdss.vat.dai(address(guest)), 50 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 20 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);

        guestPush();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(rdss.vat.sin(address(guest)), 0);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf - int256(30 * RAD));
        guestDomain.relayToHost(true);

        assertEq(dss.vat.dai(address(dss.vow)), vowDai + 30 * RAD);
        assertEq(dss.vat.sin(address(dss.vow)), vowSin);
        assertEq(dss.dai.balanceOf(escrow), escrowDai + 70 ether);
    }

    function testPushDeficit() public {
        uint256 escrowDai = dss.dai.balanceOf(escrow);
        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 vowSin = dss.vat.sin(address(dss.vow));
        guestDomain.selectFork();
        int256 existingSurf = Vat(address(rdss.vat)).surf();
        rootDomain.selectFork();

        // Set global DC and add 20 DAI surplus + 50 DAI debt to vow
        hostLift(100 ether);
        guestDomain.relayFromHost(true);
        
        rdss.vat.suck(address(123), address(guest), 20 * RAD);
        rdss.vat.suck(address(guest), address(123), 50 * RAD);

        assertEq(rdss.vat.dai(address(guest)), 20 * RAD);
        assertEq(rdss.vat.sin(address(guest)), 50 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);

        guestPush();
        guestDomain.relayToHost(true);

        guestDomain.selectFork();
        assertEq(rdss.vat.dai(address(guest)), 0);
        assertEq(rdss.vat.sin(address(guest)), 30 * RAD);
        assertEq(Vat(address(rdss.vat)).surf(), existingSurf);
        rootDomain.selectFork();

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
        assertEq(pip.read(), bytes32(WAD));

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

        rootDomain.selectFork();
        dss.end.cage();
        host.deny(address(this));       // Confirm cage can be done permissionlessly
        hostCage();

        // Verify cannot cage the host ilk until a final cure is reported
        assertRevert(address(dss.end), abi.encodeWithSignature("cage(bytes32)", ilk), "BridgeOracle/haz-not");

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
        assertEq(guest.grain(), 100 ether);
        rdss.end.flow(GUEST_COLL_ILK);
        guestDomain.relayToHost(true);
        assertEq(host.cure(), 60 * RAD);    // 60 pre-mint dai is unused

        // --- Settle out the Host instance ---

        (ink, art) = dss.vat.urns(ilk, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(dss.vat.gem(ilk, address(dss.end)), 0);
        uint256 vowSin = dss.vat.sin(address(dss.vow));

        dss.end.cage(ilk);

        assertEq(dss.end.tag(ilk), 25 * RAY / 10);   // Tag should be 2.5 (1 / $1 * 40% debt used)
        assertEq(dss.end.gap(ilk), 0);

        dss.end.skim(ilk, address(host));

        assertEq(dss.end.gap(ilk), 150 * WAD);
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
        dss.cure.load(address(host));
        dss.end.thaw();

        assertEq(dss.end.debt(), debt - 60 * RAD);

        dss.end.flow(ilk);

        assertEq(dss.end.fix(ilk), (100 * RAD) / (dss.end.debt() / RAY));

        // --- Do user redemption for guest domain collateral ---

        // Pretend you own 50% of all outstanding debt (should be a pro-rate claim on $20 for the guest domain)
        uint256 myDai = (dss.end.debt() / 2) / RAY;
        dss.vat.suck(address(123), address(this), myDai * RAY);
        dss.vat.hope(address(dss.end));

        // Pack all your DAI
        assertEq(dss.end.bag(address(this)), 0);
        dss.end.pack(myDai);
        assertEq(dss.end.bag(address(this)), myDai);

        // Should get 50 gems valued at $0.40 each
        assertEq(dss.vat.gem(ilk, address(this)), 0);
        dss.end.cash(ilk, myDai);
        uint256 gems = dss.vat.gem(ilk, address(this));
        assertApproxEqRel(gems, 50 ether, WAD / 10000);

        // Exit to the guest domain
        hostExit(address(this), gems);
        assertEq(dss.vat.gem(ilk, address(this)), 0);
        guestDomain.relayFromHost(true);
        uint256 tokens = claimToken.balanceOf(address(this));
        assertApproxEqAbs(tokens, 20 ether, WAD / 10000);

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
        rootDomain.selectFork();

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
        rootDomain.selectFork();

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
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: "host-domain",
            targetDomain: "guest-domain",
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        // Host -> Guest
        host.registerMint(teleport);
        hostInitializeRegisterMint(teleport);
        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleport);
        guestDomain.relayFromHost(true);

        // Guest -> Host
        guest.registerMint(teleport);
        guestInitializeRegisterMint(teleport);
        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleport);
        guestDomain.relayToHost(true);
    }

    function testSettle() public {
        // Host -> Guest
        dss.dai.mint(address(host), 100 ether);
        host.settle("host-domain", "guest-domain", 100 ether);
        hostInitializeSettle(0);
        guestDomain.relayFromHost(true);
        assertEq(rdss.dai.balanceOf(address(guestRouter)), 100 ether);

        // Guest -> Host
        rdss.dai.setBalance(address(guest), 50 ether);
        guest.settle("guest-domain", "host-domain", 50 ether);
        guestInitializeSettle(0);
        guestDomain.relayToHost(true);
        assertEq(dss.dai.balanceOf(address(hostRouter)), 50 ether);
    }

}
