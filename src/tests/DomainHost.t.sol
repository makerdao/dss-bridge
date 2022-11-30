// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "dss-test/DSSTest.sol";

import { DaiJoinMock } from "./mocks/DaiJoinMock.sol";
import { DaiMock } from "./mocks/DaiMock.sol";
import { EscrowMock } from "./mocks/EscrowMock.sol";
import { RouterMock } from "./mocks/RouterMock.sol";
import { VatMock } from "./mocks/VatMock.sol";
import { DomainHost, DomainGuestLike, TeleportGUID, getGUIDHash } from "../DomainHost.sol";
import "../TeleportGUID.sol";

contract EmptyDomainHost is DomainHost {

    bool forceIsGuest = true;
    bytes public lastPayload;

    constructor(bytes32 _ilk, address _daiJoin, address _escrow, address _router) DomainHost(_ilk, _daiJoin, _escrow, _router) {}

    modifier guestOnly {
        require(forceIsGuest, "DomainHost/not-guest");
        _;
    }
    function setIsGuest(bool v) external {
        forceIsGuest = v;
    }

    function deposit(address to, uint256 amount) external {
        _deposit(to, amount);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.deposit.selector, to, amount);
    }
    function deposit(bytes32 to, uint256 amount) external {
        _deposit(to, amount);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.deposit.selector, to, amount);
    }
    function undoDeposit(address sender, address to, uint256 amount) external {
        _undoDeposit(sender, to, amount);
    }
    function undoDeposit(address sender, bytes32 to, uint256 amount) external {
        _undoDeposit(sender, to, amount);
    }
    function withdraw(address to, uint256 amount) external guestOnly {
        _withdraw(to, amount);
    }
    function lift(uint256 wad) external {
        uint256 _rid = _lift(wad);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.lift.selector, _rid, wad);
    }
    function release(uint256 _lid, uint256 wad) external guestOnly {
        _release(_lid, wad);
    }
    function push(uint256 _lid, int256 wad) external guestOnly {
        _push(_lid, wad);
    }
    function rectify() external {
        (uint256 _rid, uint256 _wad) = _rectify();
        lastPayload = abi.encodeWithSelector(DomainGuestLike.rectify.selector, _rid, _wad);
    }
    function cage() external {
        (uint256 _rid) = _cage();
        lastPayload = abi.encodeWithSelector(DomainGuestLike.cage.selector, _rid);
    }
    function tell(uint256 _lid, uint256 value) external guestOnly {
        _tell(_lid, value);
    }
    function exit(address usr, uint256 wad) external {
        _exit(usr, wad);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.exit.selector, usr, wad);
    }
    function exit(bytes32 usr, uint256 wad) external {
        _exit(usr, wad);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.exit.selector, usr, wad);
    }
    function undoExit(address sender, address usr, uint256 wad) external {
        _undoExit(sender, usr, wad);
    }
    function undoExit(address sender, bytes32 usr, uint256 wad) external {
        _undoExit(sender, usr, wad);
    }
    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        _initializeRegisterMint(teleport);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.finalizeRegisterMint.selector, teleport);
    }
    function finalizeRegisterMint(TeleportGUID calldata teleport) external guestOnly {
        _finalizeRegisterMint(teleport);
    }
    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) external {
        uint256 _amount = _initializeSettle(sourceDomain, targetDomain);
        lastPayload = abi.encodeWithSelector(DomainGuestLike.finalizeSettle.selector, sourceDomain, targetDomain, _amount);
    }
    function undoInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external {
        _undoInitializeSettle(sourceDomain, targetDomain, amount);
    }
    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external guestOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }

}

contract DomainHostTest is DSSTest {

    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    EscrowMock escrow;
    RouterMock router;
    address vow;

    EmptyDomainHost host;

    bytes32 constant ILK = "SOME-DOMAIN-A";
    bytes32 constant SOURCE_DOMAIN = "SOME-DOMAIN-B";
    bytes32 constant TARGET_DOMAIN = "SOME-DOMAIN-C";

    event Lift(uint256 wad);
    event Release(uint256 wad);
    event Push(int256 wad);
    event Rectify(uint256 wad);
    event Cage();
    event Tell(uint256 value);
    event Exit(address indexed sender, address indexed usr, uint256 wad);
    event Exit(address indexed sender, bytes32 indexed usr, uint256 wad);
    event UndoExit(address indexed sender, address indexed usr, uint256 wad);
    event UndoExit(address indexed sender, bytes32 indexed usr, uint256 wad);
    event Deposit(address indexed sender, address indexed to, uint256 amount);
    event Deposit(address indexed sender, bytes32 indexed to, uint256 amount);
    event UndoDeposit(address indexed sender, address indexed to, uint256 amount);
    event UndoDeposit(address indexed sender, bytes32 indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event RegisterMint(TeleportGUID teleport);
    event InitializeRegisterMint(TeleportGUID teleport);
    event FinalizeRegisterMint(TeleportGUID teleport);
    event Settle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event InitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event UndoInitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event FinalizeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);

    function postSetup() internal virtual override {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        escrow = new EscrowMock();
        vow = address(123);
        router = new RouterMock(address(dai));

        host = new EmptyDomainHost(ILK, address(daiJoin), address(escrow), address(router));
        host.file("vow", vow);

        escrow.approve(address(dai), address(host), type(uint256).max);
        vat.hope(address(daiJoin));
    }

    function testConstructor() public {
        assertEq(host.ilk(), ILK);
        assertEq(address(host.vat()), address(vat));
        assertEq(address(host.daiJoin()), address(daiJoin));
        assertEq(address(host.dai()), address(dai));
        assertEq(address(host.escrow()), address(escrow));
        assertEq(address(host.router()), address(router));

        assertEq(vat.can(address(host), address(daiJoin)), 1);
        assertEq(dai.allowance(address(host), address(daiJoin)), type(uint256).max);
        assertEq(dai.allowance(address(host), address(router)), type(uint256).max);
        assertEq(host.wards(address(this)), 1);
        assertEq(host.live(), 1);
    }

    function testRelyDeny() public {
        checkAuth(address(host), "DomainHost");
    }

    function testFile() public {
        checkFileAddress(address(host), "DomainHost", ["vow"]);
    }

    function testAuth() public {
        host.deny(address(this));

        bytes[] memory funcs = new bytes[](2);
        funcs[0] = abi.encodeWithSelector(EmptyDomainHost.lift.selector, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainHost.rectify.selector);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(host), funcs[i], "DomainHost/not-authorized");
        }
    }

    function testGuestOnly() public {
        host.setIsGuest(false);

        bytes[] memory funcs = new bytes[](6);
        funcs[0] = abi.encodeWithSelector(EmptyDomainHost.release.selector, 0, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainHost.push.selector, 0, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainHost.tell.selector, 0, 0, 0);
        funcs[3] = abi.encodeWithSelector(EmptyDomainHost.withdraw.selector, 0, 0, 0);
        funcs[4] = abi.encodeWithSelector(EmptyDomainHost.finalizeRegisterMint.selector, 0, 0, 0, 0, 0, 0, 0);
        funcs[5] = abi.encodeWithSelector(EmptyDomainHost.finalizeSettle.selector, 0, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(host), funcs[i], "DomainHost/not-guest");
        }
    }

    function testVatLive() public {
        vat.cage();

        bytes[] memory funcs = new bytes[](3);
        funcs[0] = abi.encodeWithSelector(EmptyDomainHost.lift.selector, 0, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainHost.release.selector, 0, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainHost.rectify.selector, 0, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(host), funcs[i], "DomainHost/vat-not-live");
        }
    }

    function testOrdered() public {
        bytes[] memory funcs = new bytes[](3);
        funcs[0] = abi.encodeWithSelector(EmptyDomainHost.release.selector, 1, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainHost.push.selector, 1, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainHost.tell.selector, 1, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(host), funcs[i], "DomainHost/out-of-order");
        }
    }

    function testLift() public {
        // Set DC to 100
        vm.expectEmit(true, true, true, true);
        emit Lift(100 ether);
        host.lift(100 ether);

        (uint256 ink, uint256 art) = vat.urns(ILK, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.line(), 100 * RAD);
        assertEq(host.grain(), 100 ether);
        assertEq(host.rid(), 1);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 0, 100 * WAD));

        // Raise DC to 200
        host.lift(200 ether);

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 200 ether);
        assertEq(art, 200 ether);
        assertEq(dai.balanceOf(address(escrow)), 200 ether);
        assertEq(host.line(), 200 * RAD);
        assertEq(host.grain(), 200 ether);
        assertEq(host.rid(), 2);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 1, 200 * WAD));

        // Lower DC back to 100 - should not remove escrowed DAI
        host.lift(100 ether);

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 200 ether);
        assertEq(art, 200 ether);
        assertEq(dai.balanceOf(address(escrow)), 200 ether);
        assertEq(host.line(), 100 * RAD);
        assertEq(host.grain(), 200 ether);
        assertEq(host.rid(), 3);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 2, 100 * WAD));
    }

    function testRelease() public {
        // Set DC to 100
        host.lift(100 ether);

        (uint256 ink, uint256 art) = vat.urns(ILK, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.line(), 100 * RAD);
        assertEq(host.grain(), 100 ether);
        assertEq(host.rid(), 1);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 0, 100 * WAD));

        // Lower DC back to 50 - should not remove escrowed DAI
        host.lift(50 ether);

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(host.grain(), 100 ether);
        assertEq(host.rid(), 2);
        assertEq(host.lid(), 0);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 1, 50 * WAD));

        // Remote domain triggers release at a later time
        vm.expectEmit(true, true, true, true);
        emit Release(50 ether);
        host.release(0, 50 ether);

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);
        assertEq(dai.balanceOf(address(escrow)), 50 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(host.grain(), 50 ether);
        assertEq(host.lid(), 1);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 1, 50 * WAD));
    }

    function testReleasePermissionlessRepay() public {
        vat.suck(address(456), address(this), 1 * RAD);
        host.lift(100 ether);
        host.lift(0);

        (uint256 ink, uint256 art) = vat.urns(ILK, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 100 ether);
        
        // Repay some dust
        vat.frob(ILK, address(host), address(this), address(this), 0, -int256(1 ether));

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 100 ether);
        assertEq(art, 99 ether);
        assertEq(vat.sin(vow), 0);
        assertEq(vat.dai(vow), 0);

        // Should not block releasing all DAI
        host.release(0, 100 ether);

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(vat.sin(vow), 0);
        assertEq(vat.dai(vow), 1 * RAD);
    }

    function testComplexLiftRelease() public {
        host.lift(100 ether);
        host.lift(50 ether);        // Trigger lowering
        host.lift(75 ether);        // Trigger raise before the release comes in
        host.lift(50 ether);        // Trigger another lowering

        (uint256 ink, uint256 art) = vat.urns(ILK, address(host));
        assertEq(ink, 125 ether);
        assertEq(art, 125 ether);
        assertEq(dai.balanceOf(address(escrow)), 125 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(host.grain(), 125 ether);
        assertEq(host.rid(), 4);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 3, 50 * WAD));

        host.release(0, 50 ether);   // First release comes in

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 75 ether);
        assertEq(art, 75 ether);
        assertEq(dai.balanceOf(address(escrow)), 75 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(host.grain(), 75 ether);
        assertEq(host.lid(), 1);
        assertEq(host.rid(), 4);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 3, 50 * WAD));

        host.release(1, 25 ether);   // Second release comes in

        (ink, art) = vat.urns(ILK, address(host));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);
        assertEq(dai.balanceOf(address(escrow)), 50 ether);
        assertEq(host.line(), 50 * RAD);
        assertEq(host.grain(), 50 ether);
        assertEq(host.lid(), 2);
        assertEq(host.rid(), 4);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.lift.selector, 3, 50 * WAD));
    }

    function testPushSurplus() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(escrow), 100 ether);

        assertEq(vat.dai(vow), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.sin(), 0);
        assertEq(host.lid(), 0);

        vm.expectEmit(true, true, true, true);
        emit Push(int256(100 ether));
        host.push(0, int256(100 ether));

        assertEq(vat.dai(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(escrow)), 0);
        assertEq(host.sin(), 0);
        assertEq(host.lid(), 1);
    }

    function testPushDeficit() public {
        assertEq(host.sin(), 0);

        vm.expectEmit(true, true, true, true);
        emit Push(-int256(100 ether));
        host.push(0, -int256(100 ether));

        assertEq(host.sin(), 100 ether);
    }

    function testRectify() public {
        host.push(0, -int256(100 ether));

        assertEq(vat.sin(vow), 0);
        assertEq(dai.balanceOf(address(escrow)), 0);
        assertEq(host.sin(), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Rectify(100 ether);
        host.rectify();

        assertEq(vat.sin(vow), 100 * RAD);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.rectify.selector, 0, 100 ether));
    }

    function testRectifyNoSin() public {
        vm.expectRevert("DomainHost/no-sin");
        host.rectify();
    }

    function testCage() public {
        // Can cage now
        vm.expectEmit(true, true, true, true);
        emit Cage();
        host.cage();

        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.cage.selector, 0));
    }

    function testCagePermissionlessly() public {
        host.deny(address(this));

        // Cannot cage when vat is live
        vm.expectRevert("DomainHost/not-authorized");
        host.cage();

        // Cage the vat
        vat.cage();

        // Can cage now
        vm.expectEmit(true, true, true, true);
        emit Cage();
        host.cage();

        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.cage.selector, 0));
    }

    function testCageTwice() public {
        host.cage();

        vm.expectRevert("DomainHost/not-live");
        host.cage();
    }

    function testTell() public {
        host.lift(100 ether);
        host.cage();

        assertEq(host.cure(), 0);
        assertTrue(!host.cureReported());

        vm.expectEmit(true, true, true, true);
        emit Tell(100 * RAD);
        host.tell(0, 100 * RAD);

        assertEq(host.cure(), 100 * RAD);
        assertTrue(host.cureReported());
    }

    function testTellNotCaged() public {
        host.lift(100 ether);

        vm.expectRevert("DomainHost/live");
        host.tell(0, 100 * RAD);
    }

    function testTellCureBadValue() public {
        host.lift(50 ether);
        host.cage();

        vm.expectRevert("DomainHost/cure-bad-value");
        host.tell(0, 100 * RAD);
    }

    function testTellTwice() public {
        host.lift(100 ether);
        host.cage();
        host.tell(0, 100 * RAD);

        vm.expectRevert("DomainHost/cure-reported");
        host.tell(1, 50 * RAD);
    }

    function testExit() public {
        // Setup initial conditions
        host.lift(100 ether);       // DC raised to 100
        vat.cage();
        host.cage();
        host.tell(0, 70 * RAD);        // Guest later reports on 30 debt is actually used

        // Simulate user getting some gems for this ilk (normally handled by end)
        vat.slip(ILK, address(this), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Exit(address(this), address(123), 50 ether);
        host.exit(address(123), 50 ether);

        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.exit.selector, address(123), 50 ether));
    }

    function testExitBytes32() public {
        // Setup initial conditions
        host.lift(100 ether);       // DC raised to 100
        vat.cage();
        host.cage();
        host.tell(0, 70 * RAD);        // Guest later reports on 30 debt is actually used

        // Simulate user getting some gems for this ilk (normally handled by end)
        vat.slip(ILK, address(this), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Exit(address(this), bytes32(uint256(123)), 50 ether);
        host.exit(bytes32(uint256(123)), 50 ether);

        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.exit.selector, address(123), 50 ether));
    }

    function testUndoExit() public {
        // Setup initial conditions
        host.lift(100 ether);       // DC raised to 100
        vat.cage();
        host.cage();
        host.tell(0, 70 * RAD);        // Guest later reports on 30 debt is actually used

        // Simulate user getting some gems for this ilk (normally handled by end)
        vat.slip(ILK, address(this), 50 ether);

        // User attempts to exit
        host.exit(address(123), 50 ether);

        assertEq(vat.gem(ILK, address(this)), 0);

        // ... but they were censored and user wants the funds back
        vm.expectEmit(true, true, true, true);
        emit UndoExit(address(this), address(123), 50 ether);
        host.undoExit(address(this), address(123), 50 ether);

        assertEq(vat.gem(ILK, address(this)), 50 ether);
    }

    function testUndoExitBytes32() public {
        // Setup initial conditions
        host.lift(100 ether);       // DC raised to 100
        vat.cage();
        host.cage();
        host.tell(0, 70 * RAD);        // Guest later reports on 30 debt is actually used

        // Simulate user getting some gems for this ilk (normally handled by end)
        vat.slip(ILK, address(this), 50 ether);

        // User attempts to exit
        host.exit(bytes32(uint256(123)), 50 ether);

        assertEq(vat.gem(ILK, address(this)), 0);

        // ... but they were censored and user wants the funds back
        vm.expectEmit(true, true, true, true);
        emit UndoExit(address(this), bytes32(uint256(123)), 50 ether);
        host.undoExit(address(this), bytes32(uint256(123)), 50 ether);

        assertEq(vat.gem(ILK, address(this)), 50 ether);
    }

    function testDeposit() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(123), 100 ether);
        host.deposit(address(123), 100 ether);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.deposit.selector, address(123), 100 ether));
    }

    function testDepositBytes32() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), bytes32(uint256(123)), 100 ether);
        host.deposit(bytes32(uint256(123)), 100 ether);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.deposit.selector, address(123), 100 ether));
    }

    function testUndoDeposit() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        // User attempts to deposit
        host.deposit(address(123), 100 ether);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);

        // ... but they were censored and user wants the funds back
        vm.expectEmit(true, true, true, true);
        emit UndoDeposit(address(this), address(123), 100 ether);
        host.undoDeposit(address(this), address(123), 100 ether);

        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);
    }

    function testUndoDepositBytes32() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        // User attempts to deposit
        host.deposit(bytes32(uint256(123)), 100 ether);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);

        // ... but they were censored and user wants the funds back
        vm.expectEmit(true, true, true, true);
        emit UndoDeposit(address(this), bytes32(uint256(123)), 100 ether);
        host.undoDeposit(address(this), bytes32(uint256(123)), 100 ether);

        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);
    }

    function testWithdraw() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(escrow), 100 ether);

        assertEq(dai.balanceOf(address(123)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(123), 100 ether);
        host.withdraw(address(123), 100 ether);

        assertEq(dai.balanceOf(address(123)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);
    }

    function testRegisterMint() public {
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: SOURCE_DOMAIN,
            targetDomain: TARGET_DOMAIN,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        assertEq(host.teleports(getGUIDHash(teleport)), false);

        vm.expectEmit(true, true, true, true);
        emit RegisterMint(teleport);
        host.registerMint(teleport);

        assertEq(host.teleports(getGUIDHash(teleport)), true);
    }

    function testInitializeRegisterMint() public {
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: SOURCE_DOMAIN,
            targetDomain: TARGET_DOMAIN,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        host.registerMint(teleport);

        vm.expectEmit(true, true, true, true);
        emit InitializeRegisterMint(teleport);
        host.initializeRegisterMint(teleport);

        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.finalizeRegisterMint.selector, teleport));
    }

    function testInitializeRegisterMintNotRegistered() public {
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: SOURCE_DOMAIN,
            targetDomain: TARGET_DOMAIN,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        vm.expectRevert("DomainHost/teleport-not-registered");
        host.initializeRegisterMint(teleport);
    }

    function testFinalizeRegisterMint() public {
        TeleportGUID memory teleport = TeleportGUID({
            sourceDomain: SOURCE_DOMAIN,
            targetDomain: TARGET_DOMAIN,
            receiver: bytes32(0),
            operator: bytes32(0),
            amount: 100 ether,
            nonce: 0,
            timestamp: uint48(block.timestamp)
        });

        host.finalizeRegisterMint(teleport);

        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleport);
        host.finalizeRegisterMint(teleport);
    }

    function testSettle() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(host), 100 ether);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 0);
        assertEq(dai.balanceOf(address(escrow)), 0);

        vm.expectEmit(true, true, true, true);
        emit Settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        host.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);
    }

    function testInitializeSettle() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(host), 100 ether);

        host.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit InitializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        host.initializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 0);
        assertEq(host.lastPayload(), abi.encodeWithSelector(DomainGuestLike.finalizeSettle.selector, SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether));
    }

    function testInitializeSettleNotFound() public {
        vm.expectRevert("DomainHost/settlement-zero");
        host.initializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN);
    }

    function testUndoInitializeSettle() public {
        vat.suck(address(123), address(this), 150 * RAD);
        daiJoin.exit(address(host), 150 ether);

        host.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        host.initializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN);
        host.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 50 ether);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit UndoInitializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        host.undoInitializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(host.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 150 ether);
    }

    function testFinalizeSettle() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(escrow), 100 ether);

        assertEq(dai.balanceOf(address(router)), 0);
        assertEq(dai.balanceOf(address(escrow)), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit FinalizeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        host.finalizeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(dai.balanceOf(address(router)), 100 ether);
        assertEq(dai.balanceOf(address(escrow)), 0);
    }

}
