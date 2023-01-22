// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "dss-test/DssTest.sol";

import { Escrow } from "../Escrow.sol";
import { DaiMock } from "./mocks/DaiMock.sol";

contract EscrowTest is DssTest {
    Escrow escrow;
    DaiMock dai;

    event Approve(address indexed token, address indexed spender, uint256 value);

    function setUp() public {
        escrow = new Escrow();
        dai = new DaiMock();
    }

    function testRelyDeny() public {
        checkAuth(address(escrow), "Escrow");
    }

    function testApprove() public {
        address spender = address(1234);
        dai.mint(address(escrow), 1000);
        assertEq(dai.balanceOf(address(escrow)), 1000);
        assertEq(dai.balanceOf(address(spender)), 0);
        assertEq(dai.allowance(address(escrow), spender), 0);
        vm.expectRevert("Dai/insufficient-allowance");
        vm.prank(spender);
        dai.transferFrom(address(escrow), spender, 500);
        vm.expectEmit(true, true, true, true);
        emit Approve(address(dai), spender, 500);
        escrow.approve(address(dai), spender, 500);
        assertEq(dai.allowance(address(escrow), spender), 500);
        vm.prank(spender);
        dai.transferFrom(address(escrow), spender, 500);
        assertEq(dai.balanceOf(address(escrow)), 500);
        assertEq(dai.balanceOf(address(spender)), 500);
        assertEq(dai.allowance(address(escrow), spender), 0);
    }
}
