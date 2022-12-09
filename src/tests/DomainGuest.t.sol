// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "dss-test/DSSTest.sol";

import { DaiJoinMock } from "./mocks/DaiJoinMock.sol";
import { DaiMock } from "./mocks/DaiMock.sol";
import { EndMock } from "./mocks/EndMock.sol";
import { EscrowMock } from "./mocks/EscrowMock.sol";
import { RouterMock } from "./mocks/RouterMock.sol";
import { VatMock } from "./mocks/VatMock.sol";
import { DomainGuest, DomainHostLike, TeleportGUID, getGUIDHash } from "../DomainGuest.sol";

contract EmptyDomainGuest is DomainGuest {

    bool forceIsHost = true;
    bytes public lastPayload;

    constructor(address _daiJoin, address _claimToken, address _router) DomainGuest(_daiJoin, _claimToken, _router) {}

    modifier hostOnly {
        require(forceIsHost, "DomainGuest/not-host");
        _;
    }
    function setIsHost(bool v) external {
        forceIsHost = v;
    }

    function deposit(address to, uint256 amount) external hostOnly {
        _deposit(to, amount);
    }
    function withdraw(address to, uint256 amount) external {
        _withdraw(to, amount);
        lastPayload = abi.encodeWithSelector(DomainHostLike.withdraw.selector, to, amount);
    }
    function lift(uint256 _lid, uint256 wad) external hostOnly {
        _lift(_lid, wad);
    }
    function release() external {
        (uint256 _rid, uint256 _burned) = _release();
        lastPayload = abi.encodeWithSelector(DomainHostLike.release.selector, _rid, _burned);
    }
    function surplus() external {
        (uint256 _rid, uint256 _wad) = _surplus();
        lastPayload = abi.encodeWithSelector(DomainHostLike.surplus.selector, _rid, _wad);
    }
    function deficit() external {
        (uint256 _rid, uint256 _wad) = _deficit();
        lastPayload = abi.encodeWithSelector(DomainHostLike.deficit.selector, _rid, _wad);
    }
    function rectify(uint256 _lid, uint256 wad) external hostOnly {
        _rectify(_lid, wad);
    }
    function cage(uint256 _lid) external hostOnly {
        _cage(_lid);
    }
    function tell() external {
        (uint256 _rid, uint256 _cure) = _tell();
        lastPayload = abi.encodeWithSelector(DomainHostLike.tell.selector, _rid, _cure);
    }
    function exit(address usr, uint256 wad) external hostOnly {
        _exit(usr, wad);
    }
    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        _initializeRegisterMint(teleport);
        lastPayload = abi.encodeWithSelector(DomainHostLike.finalizeRegisterMint.selector, teleport);
    }
    function finalizeRegisterMint(TeleportGUID calldata teleport) external hostOnly {
        _finalizeRegisterMint(teleport);
    }
    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) external {
        uint256 _amount = _initializeSettle(sourceDomain, targetDomain);
        lastPayload = abi.encodeWithSelector(DomainHostLike.finalizeSettle.selector, sourceDomain, targetDomain, _amount);
    }
    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external hostOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }

}

contract ClaimTokenMock {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint256 amount) external {
        balanceOf[usr] += amount;
    }
}

contract DomainGuestTest is DSSTest {

    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    EndMock end;
    RouterMock router;

    DaiMock claimToken;
    EmptyDomainGuest guest;

    bytes32 constant SOURCE_DOMAIN = "SOME-DOMAIN-A";
    bytes32 constant TARGET_DOMAIN = "SOME-DOMAIN-B";

    event Lift(uint256 wad);
    event Release(uint256 burned);
    event Surplus(uint256 wad);
    event Deficit(uint256 wad);
    event Rectify(uint256 wad);
    event Cage();
    event Tell(uint256 value);
    event Exit(address indexed usr, uint256 wad);
    event Deposit(address indexed to, uint256 amount);
    event Withdraw(address indexed sender, address indexed to, uint256 amount);
    event RegisterMint(TeleportGUID teleport);
    event InitializeRegisterMint(TeleportGUID teleport);
    event FinalizeRegisterMint(TeleportGUID teleport);
    event Settle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event InitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event FinalizeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);

    function postSetup() internal virtual override {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        end = new EndMock(address(vat));
        router = new RouterMock(address(dai));

        claimToken = new DaiMock();
        guest = new EmptyDomainGuest(address(daiJoin), address(claimToken), address(router));
        guest.file("end", address(end));

        vat.hope(address(daiJoin));
        dai.approve(address(guest), type(uint256).max);
    }

    function testConstructor() public {
        assertEq(address(guest.vat()), address(vat));
        assertEq(address(guest.daiJoin()), address(daiJoin));
        assertEq(address(guest.dai()), address(dai));
        assertEq(address(guest.router()), address(router));

        assertEq(vat.can(address(guest), address(daiJoin)), 1);
        assertEq(dai.allowance(address(guest), address(daiJoin)), type(uint256).max);
        assertEq(dai.allowance(address(guest), address(router)), type(uint256).max);
        assertEq(guest.wards(address(this)), 1);
        assertEq(guest.live(), 1);
    }

    function testRelyDeny() public {
        checkAuth(address(guest), "DomainGuest");
    }

    function testFile() public {
        checkFileAddress(address(guest), "DomainGuest", ["end"]);
        checkFileUint(address(guest), "DomainGuest", ["dust"]);
    }

    function testHostOnly() public {
        guest.setIsHost(false);

        bytes[] memory funcs = new bytes[](7);
        funcs[0] = abi.encodeWithSelector(EmptyDomainGuest.lift.selector, 0, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainGuest.rectify.selector, 0, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainGuest.cage.selector, 0, 0, 0);
        funcs[3] = abi.encodeWithSelector(EmptyDomainGuest.exit.selector, 0, 0, 0);
        funcs[4] = abi.encodeWithSelector(EmptyDomainGuest.deposit.selector, 0, 0, 0);
        funcs[5] = abi.encodeWithSelector(EmptyDomainGuest.finalizeRegisterMint.selector, 0, 0, 0, 0, 0, 0, 0);
        funcs[6] = abi.encodeWithSelector(EmptyDomainGuest.finalizeSettle.selector, 0, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(guest), funcs[i], "DomainGuest/not-host");
        }
    }

    function testLive() public {
        guest.cage(0);

        bytes[] memory funcs = new bytes[](5);
        funcs[0] = abi.encodeWithSelector(EmptyDomainGuest.lift.selector, 1, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainGuest.release.selector, 0, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainGuest.surplus.selector, 0, 0, 0);
        funcs[3] = abi.encodeWithSelector(EmptyDomainGuest.deficit.selector, 0, 0, 0);
        funcs[4] = abi.encodeWithSelector(EmptyDomainGuest.cage.selector, 1, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(guest), funcs[i], "DomainGuest/not-live");
        }
    }

    function testOrdered() public {
        bytes[] memory funcs = new bytes[](3);
        funcs[0] = abi.encodeWithSelector(EmptyDomainGuest.lift.selector, 1, 0, 0);
        funcs[1] = abi.encodeWithSelector(EmptyDomainGuest.rectify.selector, 1, 0, 0);
        funcs[2] = abi.encodeWithSelector(EmptyDomainGuest.cage.selector, 1, 0, 0);

        for (uint256 i = 0; i < funcs.length; i++) {
            assertRevert(address(guest), funcs[i], "DomainGuest/out-of-order");
        }
    }

    function testLift() public {
        assertEq(guest.grain(), 0);
        assertEq(vat.Line(), 0);
        assertEq(guest.lid(), 0);

        vm.expectEmit(true, true, true, true);
        emit Lift(100 * WAD);
        guest.lift(0, 100 * WAD);

        assertEq(guest.grain(), 100 ether);
        assertEq(vat.Line(), 100 * RAD);
        assertEq(guest.lid(), 1);
    }

    function testRelease() public {
        // Set debt ceiling to 100 DAI
        guest.lift(0, 100 * WAD);

        assertEq(guest.grain(), 100 ether);
        assertEq(vat.Line(), 100 * RAD);
        assertEq(guest.lid(), 1);

        // Lower debt ceiling to 50 DAI
        guest.lift(1, 50 * WAD);

        assertEq(guest.grain(), 100 ether);
        assertEq(vat.Line(), 50 * RAD);
        assertEq(guest.lid(), 2);

        // Should release 50 DAI because nothing has been minted
        vm.expectEmit(true, true, true, true);
        emit Release(50 ether);
        guest.release();

        assertEq(guest.grain(), 50 ether);
        assertEq(vat.Line(), 50 * RAD);
        assertEq(guest.lid(), 2);
        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.release.selector, 0, 50 ether));
    }

    function testReleaseDebtTaken() public {
        // Set so that debt is larger than the global DC
        guest.lift(0, 100 * WAD);
        vat.suck(address(this), address(this), 50 * RAD);
        guest.lift(1, 0);

        assertEq(vat.Line(), 0);
        assertEq(vat.debt(), 50 * RAD);
        assertEq(guest.grain(), 100 ether);
        assertEq(guest.lid(), 2);
        assertEq(guest.rid(), 0);

        // Should only release 50 DAI
        guest.release();

        assertEq(vat.Line(), 0);
        assertEq(vat.debt(), 50 * RAD);
        assertEq(guest.grain(), 50 ether);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.release.selector, 0, 50 ether));
        assertEq(guest.rid(), 1);

        // Repay the loan and release
        vat.heal(50 * RAD);
        guest.release();

        assertEq(vat.Line(), 0);
        assertEq(vat.debt(), 0);
        assertEq(guest.grain(), 0);
        assertEq(guest.rid(), 2);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.release.selector, 1, 50 ether));
    }

    function testReleaseDust() public {
        guest.file("dust", 100 ether);

        // Set debt ceiling to 100 DAI
        guest.lift(0, 100 * WAD);

        assertEq(guest.grain(), 100 ether);
        assertEq(vat.Line(), 100 * RAD);
        assertEq(guest.lid(), 1);

        // Lower debt ceiling to 50 DAI
        guest.lift(1, 50 * WAD);

        assertEq(guest.grain(), 100 ether);
        assertEq(vat.Line(), 50 * RAD);
        assertEq(guest.lid(), 2);

        // Amount to release is less than 100 DAI
        vm.expectRevert("DomainGuest/dust");
        guest.release();
    }

    function testPushSurplus() public {
        guest.file("dust", 100 ether);
        vat.suck(address(this), address(guest), 100 * RAD);

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.sin(address(guest)), 0);
        assertEq(vat.surf(), 0);

        // Will push out a surplus of 100 DAI
        vm.expectEmit(true, true, true, true);
        emit Surplus(100 ether);
        guest.surplus();

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 0);
        assertEq(vat.surf(), -int256(100 * RAD));
        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.surplus.selector, 0, 100 ether));
    }

    function testPushSurplusPartial() public {
        vat.suck(address(this), address(this), 100 * RAD);
        vat.suck(address(guest), address(guest), 25 * RAD);
        vat.move(address(this), address(guest), 100 * RAD);

        assertEq(vat.dai(address(guest)), 125 * RAD);
        assertEq(vat.sin(address(guest)), 25 * RAD);
        assertEq(vat.surf(), 0);

        // Will push out a surplus of 100 DAI (125 - 25)
        guest.surplus();

        assertEq(vat.dai(address(guest)), 25 * RAD);
        assertEq(vat.sin(address(guest)), 25 * RAD);
        guest.heal();
        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 0);
        assertEq(vat.surf(), -int256(100 * RAD));
        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.surplus.selector, 0, 100 ether));
    }

    function testPushSurplusNoneAvailable() public {
        guest.file("dust", 100 ether);
        vat.suck(address(this), address(guest), 100 * RAD);
        vat.suck(address(guest), address(this), 101 * RAD);

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.sin(address(guest)), 101 * RAD);

        vm.expectRevert("DomainGuest/non-surplus");
        guest.surplus();
    }

    function testPushSurplusDust() public {
        guest.file("dust", 101 ether);
        vat.suck(address(this), address(guest), 100 * RAD);

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.sin(address(guest)), 0);
        assertEq(vat.surf(), 0);

        vm.expectRevert("DomainGuest/dust");
        guest.surplus();
    }

    function testPushDeficit() public {
        guest.file("dust", 100 ether);
        vat.suck(address(guest), address(this), 100 * RAD);

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 100 * RAD);
        assertEq(guest.dsin(), 0);

        // Will push out a deficit of 100 DAI
        vm.expectEmit(true, true, true, true);
        emit Deficit(100 ether);
        guest.deficit();

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 100 * RAD);
        assertEq(guest.dsin(), 100 ether);
        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.deficit.selector, 0, 100 ether));

        // Can't be executed again if there is not new deficit
        vm.expectRevert("DomainGuest/non-deficit");
        guest.deficit();

        guest.file("dust", 0);
        // Can't be executed again even if dust is zero
        vm.expectRevert("DomainGuest/non-deficit");
        guest.deficit();

        guest.file("dust", 100 ether);

        // More deficit is obtained now
        vat.suck(address(guest), address(this), 200 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Deficit(200 ether);
        guest.deficit();

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 300 * RAD);
        assertEq(guest.dsin(), 300 ether);
        assertEq(guest.rid(), 2);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.deficit.selector, 1, 200 ether));
    }

    function testPushDeficitPartial() public {
        vat.suck(address(guest), address(guest), 100 * RAD);
        vat.suck(address(guest), address(this), 25 * RAD);

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.sin(address(guest)), 125 * RAD);

        // Will push out a deficit of 25 DAI (125 - 100)
        guest.deficit();

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.sin(address(guest)), 125 * RAD);
        guest.heal();
        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 25 * RAD);
        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.deficit.selector, 0, 25 ether));
    }

    function testPushDeficitNonExisting() public {
        guest.file("dust", 100 ether);
        vat.suck(address(this), address(guest), 101 * RAD);
        vat.suck(address(guest), address(this), 100 * RAD);

        assertEq(vat.dai(address(guest)), 101 * RAD);
        assertEq(vat.sin(address(guest)), 100 * RAD);

        vm.expectRevert("DomainGuest/non-deficit");
        guest.deficit();
    }

    function testPushDeficitDust() public {
        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 0);

        vm.expectRevert("DomainGuest/non-deficit");
        guest.deficit();

        guest.file("dust", 101 ether);
        vat.suck(address(guest), address(this), 100 * RAD);

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 100 * RAD);

        vm.expectRevert("DomainGuest/dust");
        guest.deficit();
    }

    function testPushDeficitRecoveredAfterPushed() public {
        guest.file("dust", 100 ether);
        vat.suck(address(guest), address(this), 100 * RAD);

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 100 * RAD);
        assertEq(guest.dsin(), 0);

        guest.deficit();

        assertEq(guest.dsin(), 100 ether);

        vat.suck(address(this), address(guest), 1 * RAD);

        assertEq(vat.dai(address(guest)), 1 * RAD);
        assertEq(vat.sin(address(guest)), 100 * RAD);

        guest.heal();

        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.sin(address(guest)), 99 * RAD);

        vm.expectRevert("DomainGuest/non-deficit-to-push");
        guest.deficit();
    }

    function testRectify() public {
        assertEq(vat.dai(address(guest)), 0);
        assertEq(vat.surf(), 0);
        assertEq(guest.lid(), 0);

        // We need to add "sin" to guest in order to call rectify
        vm.store(
            address(guest),
            bytes32(uint256(7)),
            bytes32(uint256(100 ether))
        );
        assertEq(guest.dsin(), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Rectify(100 ether);
        guest.rectify(0, 100 ether);
        assertEq(guest.dsin(), 0);

        assertEq(vat.dai(address(guest)), 100 * RAD);
        assertEq(vat.surf(), int256(100 * RAD));
        assertEq(guest.lid(), 1);
    }

    function testCage() public {
        assertEq(end.live(), 1);
        assertEq(vat.live(), 1);
        assertEq(guest.lid(), 0);

        vm.expectEmit(true, true, true, true);
        emit Cage();
        guest.cage(0);

        assertEq(end.live(), 0);
        assertEq(vat.live(), 0);
        assertEq(guest.lid(), 1);
    }

    function testTell() public {
        guest.lift(0, 100 * WAD);
        end.setDebt(10 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Tell(90 * RAD);
        guest.tell();

        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.tell.selector, 0, 90 * RAD));
    }

    function testTellCagedNoDebt() public {
        guest.cage(0);

        vm.expectEmit(true, true, true, true);
        emit Tell(0);
        guest.tell();

        assertEq(guest.rid(), 1);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.tell.selector, 0, 0));
    }

    function testTellDebtNotSet() public {
        vat.suck(address(guest), address(this), 100 * RAD);
        guest.cage(0);
        assertEq(end.debt(), 0);
        vm.expectRevert("DomainGuest/end-debt-zero");
        guest.tell();
    }

    function testExit() public {
        guest.lift(0, 100 ether);
        end.setDebt(50 * RAD);
        claimToken.mint(address(end), 100 * RAD);
        end.approve(address(claimToken), address(guest));

        assertEq(claimToken.balanceOf(address(123)), 0);

        vm.expectEmit(true, true, true, true);
        emit Exit(address(123), 100 ether);
        guest.exit(address(123), 100 ether);

        assertEq(claimToken.balanceOf(address(123)), 50 * RAD);
    }

    function testDeposit() public {
        assertEq(dai.balanceOf(address(123)), 0);
        assertEq(vat.surf(), 0);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(123), 100 ether);
        guest.deposit(address(123), 100 ether);

        assertEq(dai.balanceOf(address(123)), 100 ether);
        assertEq(vat.surf(), int256(100 * RAD));
    }

    function testWithdraw() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);

        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(vat.surf(), 0);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), address(123), 100 ether);
        guest.withdraw(address(123), 100 ether);

        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.surf(), -int256(100 * RAD));
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.withdraw.selector, address(123), 100 ether));
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

        assertEq(guest.teleports(getGUIDHash(teleport)), false);

        vm.expectEmit(true, true, true, true);
        emit RegisterMint(teleport);
        guest.registerMint(teleport);

        assertEq(guest.teleports(getGUIDHash(teleport)), true);
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

        guest.registerMint(teleport);

        vm.expectEmit(true, true, true, true);
        emit InitializeRegisterMint(teleport);
        guest.initializeRegisterMint(teleport);

        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.finalizeRegisterMint.selector, teleport));
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

        vm.expectRevert("DomainGuest/teleport-not-registered");
        guest.initializeRegisterMint(teleport);
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

        guest.finalizeRegisterMint(teleport);

        vm.expectEmit(true, true, true, true);
        emit FinalizeRegisterMint(teleport);
        guest.finalizeRegisterMint(teleport);
    }

    function testSettle() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(guest), 100 ether);

        assertEq(guest.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 0);
        assertEq(vat.surf(), 0);

        vm.expectEmit(true, true, true, true);
        emit Settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        guest.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(guest.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 100 ether);
        assertEq(vat.surf(), -int256(100 * RAD));
    }

    function testInitializeSettle() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(guest), 100 ether);

        guest.settle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit InitializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        guest.initializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN);

        assertEq(guest.settlements(SOURCE_DOMAIN, TARGET_DOMAIN), 0);
        assertEq(guest.lastPayload(), abi.encodeWithSelector(DomainHostLike.finalizeSettle.selector, SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether));
    }

    function testInitializeSettleNotFound() public {
        vm.expectRevert("DomainGuest/settlement-zero");
        guest.initializeSettle(SOURCE_DOMAIN, TARGET_DOMAIN);
    }

    function testFinalizeSettle() public {
        assertEq(dai.balanceOf(address(router)), 0);
        assertEq(vat.surf(), 0);

        vm.expectEmit(true, true, true, true);
        emit FinalizeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);
        guest.finalizeSettle(SOURCE_DOMAIN, TARGET_DOMAIN, 100 ether);

        assertEq(dai.balanceOf(address(router)), 100 ether);
        assertEq(vat.surf(), int256(100 * RAD));
    }

}
