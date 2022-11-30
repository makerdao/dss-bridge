import { DaiJoinMock } from "../mocks/DaiJoinMock.sol";
import { DaiMock } from "../mocks/DaiMock.sol";
import { EscrowMock } from "../mocks/EscrowMock.sol";
import { RouterMock } from "../mocks/RouterMock.sol";
import { VatMock } from "../mocks/VatMock.sol";
import { StarknetMock } from "../mocks/StarknetMock.sol";
import { StarknetDomainHost } from "../../domains/starknet/StarknetDomainHost.sol";
import "../../TeleportGUID.sol";

import "dss-test/DSSTest.sol";

pragma solidity ^0.8.15;

contract StarknetHostTest is DSSTest {

    event LogMessageToL2(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[] payload,
        uint256 nonce,
        uint256 fee
    );

    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    EscrowMock escrow;
    RouterMock router;
    StarknetMock starknet;
    address vow;

    StarknetDomainHost host;

    bytes32 constant ILK = "SOME-DOMAIN-A";
    bytes32 constant SOURCE_DOMAIN = "SOME-DOMAIN-B";
    bytes32 constant TARGET_DOMAIN = "SOME-DOMAIN-C";
    uint256 constant L2_DAI = 1234;
    uint256 constant GUEST = 5678;

    uint256 constant SN_PRIME =
        3618502788666131213697322783095070105623107215331596699973092056135872020481;

    uint256 constant DEPOSIT= 1; // TODO

    function postSetup() internal virtual override {
        vat = new VatMock();
        dai = new DaiMock();
        starknet = new StarknetMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        escrow = new EscrowMock();
        vow = address(123);
        router = new RouterMock(address(dai));

        host = new StarknetDomainHost(
            ILK,
            address(daiJoin),
            address(escrow),
            address(router),
            address(starknet),
            GUEST,
            L2_DAI
        );

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
        assertEq(address(host.starknet()), address(starknet));
        assertEq(host.l2Dai(), L2_DAI);

        assertEq(vat.can(address(host), address(daiJoin)), 1);
        assertEq(dai.allowance(address(host), address(daiJoin)), type(uint256).max);
        assertEq(dai.allowance(address(host), address(router)), type(uint256).max);
        assertEq(host.wards(address(this)), 1);
        assertEq(host.live(), 1);
    }

    function testDepost() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        host.setCeiling(10 ether);

        uint256 l2Address = 2345;

        uint256 depositAmount = 10 ether;
        uint256 fee = 144;

        uint256 balanceBefore = dai.balanceOf(address(this));

        (uint256 depositAmountLow, uint256 depositAmountHigh) = split(depositAmount);

        uint256[] memory payload = new uint256[](4);
        payload[0] = l2Address;
        payload[1] = depositAmountLow;
        payload[2] = depositAmountHigh;
        payload[3] = uint256(uint160(address(this)));

        vm.expectEmit(true, true, true, true);
        emit LogMessageToL2(address(host), host.guest(), DEPOSIT, payload, 0, fee);

        host.deposit{value: 144}(depositAmount, l2Address);

        assertEq(dai.balanceOf(address(this)), balanceBefore - depositAmount);

    }

    function testAddressValidation() public {
        uint256 amount = 1;

        vm.expectRevert('StarknetDomainHost/invalid-address');
        host.deposit(amount, 0);

        vm.expectRevert('StarknetDomainHost/invalid-address');
        host.deposit(amount, SN_PRIME);

        vm.expectRevert('StarknetDomainHost/invalid-address');
        host.deposit(amount, type(uint256).max);

        vm.expectRevert('StarknetDomainHost/invalid-address');
        host.deposit(amount, L2_DAI);
    }

    function testCeilingTooLow() public {
        vat.suck(address(123), address(this), 100 * RAD);
        daiJoin.exit(address(this), 100 ether);
        dai.approve(address(host), 100 ether);

        host.setCeiling(1 ether);

        uint256 l2Address = 2345;

        vm.expectRevert('StarknetDomainHost/above-ceiling');
        host.deposit(10 ether, l2Address);
    }

    function testSetCeiling() public {
        host.setCeiling(12 ether);
        assertEq(host.ceiling(), 12 ether);
    }

    function testUnauthorizedSetCeiling() public {
        host.deny(address(this));
        vm.expectRevert('DomainHost/not-authorized');
        host.setCeiling(12 ether);
    }

    function testDepositTooLarge() public {
        host.setCeiling(10 ether);
        host.setMaxDeposit(1 ether);

        uint256 l2Address = 2345;

        vm.expectRevert('StarknetDomainHost/above-max-deposit');
        host.deposit(2 ether, l2Address);
    }

    function testSetMaxDeposit() public {
        host.setMaxDeposit(12 ether);
        assertEq(host.maxDeposit(), 12 ether);
    }

    function testUnauthorizedSetMaxDeposit() public {
        host.deny(address(this));
        vm.expectRevert('DomainHost/not-authorized');
        host.setMaxDeposit(12 ether);
    }

}

function split(uint256 value) pure returns (uint256, uint256) {
    return (value & ((1 << 128) - 1), value >> 128);
}