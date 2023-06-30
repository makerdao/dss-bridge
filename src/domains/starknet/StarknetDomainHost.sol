// SPDX-License-Identifier: AGPL-3.0-or-later

/// StarknetDomainHost.sol -- DomainHost for Starknet

// Copyright (C) 2022 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.15;

import { DomainHost, DomainGuestLike, TeleportGUID } from "../../DomainHost.sol";

interface StarknetLike {
    function sendMessageToL2(
        uint256 to,
        uint256 selector,
        uint256[] calldata payload
    ) external payable returns (bytes32, uint256);

    function consumeMessageFromL2(
        uint256 from,
        uint256[] calldata payload
    ) external returns (bytes32);

    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32);

    function cancelL1ToL2Message(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32);
}

contract StarknetDomainHost is DomainHost {


    // src/starkware/cairo/lang/cairo_constants.py
    //  2 ** 251 + 17 * 2 ** 192 + 1;
    uint256 constant SN_PRIME =
        3618502788666131213697322783095070105623107215331596699973092056135872020481;

    // l1->l2 selectors
    //  from starkware.starknet.compiler.compile import get_selector_from_name
    //  print(get_selector_from_name('deposit'))
    uint256 constant DEPOSIT                  = 0x02d757788a8d8d6f21d1cd40bce38a8222d70654214e96ff95d8086e684fbee5;
    uint256 constant LIFT                     = 0x0097e0a7daa178262ccab0934871ccb7f1824e8e243b70a261b31b63a933c0d8;
    uint256 constant RECTIFY                  = 0x0011fce77b0d18edec88dd4ea11a79954603e9f58dfdea7cfa0a1e878f9ed123; 
    uint256 constant CAGE                     = 0x03a8fb615613782c5344a82b21562217b97c5751ed70241335cdf35f5df787db;
    uint256 constant EXIT                     = 0x01b94138ef066f7e697538e2b11b58ba2828c21f5a7b8c84d976f91a2bf9ea2e;
    uint256 constant INITIALIZE_REGISTER_MINT = 0x02fca9ac2f009914738bae235270207cf40bca1bcfd0857f7491e12be45a2b16;
    uint256 constant INITIALIZE_SETTLE        = 0x03fa39ec7e437e57cf90a50f74f2e0069a791c8804f01f513746510dce80eac1;

    // l2->l1 selectors
    uint256 constant WITHDRAW        = 1;
    uint256 constant RELEASE         = 2;
    uint256 constant SURPLUS         = 3;
    uint256 constant DEFICIT         = 4;
    uint256 constant TELL            = 5;
    uint256 constant REGISTER_MINT   = 6;
    uint256 constant FINALIZE_SETTLE = 7;

    // data
    StarknetLike public immutable starknet;
    uint256 public immutable l2Dai;
    uint256 public immutable guest;

    uint256 public ceiling = 0;
    uint256 public maxDeposit = type(uint256).max;

    event LogCeiling(uint256 ceiling);
    event LogMaxDeposit(uint256 maxDeposit);

    constructor(
        bytes32 _ilk,
        address _daiJoin,
        address _escrow,
        address _router,
        address _starknet,
        uint256 _guest,
        uint256 _l2Dai
    ) DomainHost(_ilk, _daiJoin, _escrow, _router) {
        starknet = StarknetLike(_starknet);
        guest = _guest;
        l2Dai = _l2Dai;
    }

    function setCeiling(uint256 _ceiling) external auth {
        ceiling = _ceiling;
        emit LogCeiling(_ceiling);
    }

    function setMaxDeposit(uint256 _maxDeposit) external auth {
        maxDeposit = _maxDeposit;
        emit LogMaxDeposit(_maxDeposit);
    }

    function depositPayload(uint256 to, uint256 amount, address sender) private pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](4);
        payload[0] = to;
        (payload[1], payload[2]) = split(amount);
        payload[3] = uint256(uint160(sender)); // deposit cancelation access control

        return payload;
    }

    // TODO: limits

    // TODO: it is starkgate convention to represent l2 addresses with uint256
    function deposit(uint256 amount, uint256 to) external payable validL2Address(to) {
        require(uint256(to) != l2Dai, "StarknetDomainHost/invalid-address");
        require(amount <= maxDeposit, "StarknetDomainHost/above-max-deposit");

        _deposit(bytes32(to), amount);

        starknet.sendMessageToL2{value: msg.value}(
            guest, DEPOSIT, depositPayload(to, amount, msg.sender)
        );

        require(dai.balanceOf(escrow) <= ceiling, "StarknetDomainHost/above-ceiling");
    }

    function startUndoDeposit(uint256 to, uint256 amount, uint256 nonce) internal {
        starknet.startL1ToL2MessageCancellation(
            guest, DEPOSIT, depositPayload(to, amount, msg.sender), nonce
        );
    }

    function undoDeposit(uint256 to, uint256 amount, uint256 nonce) internal {
        starknet.cancelL1ToL2Message(
            guest, DEPOSIT, depositPayload(to, amount, msg.sender), nonce
        );
        _undoDeposit(msg.sender, bytes32(to), amount);
    }

    // TODO: Starkgate compatibility
    function withdraw(address to, uint256 amount) external {
        _withdraw(to, amount);

        uint256[] memory payload = new uint256[](4);
        payload[0] = WITHDRAW;
        payload[1] = uint256(uint160(to)); // TODO: change versus v1, verify l2 implementation
        (payload[2], payload[3]) = split(amount);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function lift(uint256 wad) external payable {
        uint256 _rid = _lift(wad);
        uint256[] memory payload = new uint256[](4);
        (payload[0], payload[1]) = split(_rid);
        (payload[2], payload[3]) = split(wad);

        starknet.sendMessageToL2{value: msg.value}(guest, LIFT, payload);
    }

    function rectify() external payable {
        (uint256 _rid, uint256 _wad) = _rectify();
        uint256[] memory payload = new uint256[](4);
        (payload[0], payload[1]) = split(_rid);
        (payload[2], payload[3]) = split(_wad);

        starknet.sendMessageToL2{value: msg.value}(guest, RECTIFY, payload);
    }

    function cage() external payable {
        (uint256 _rid) = _cage();
        uint256[] memory payload = new uint256[](2);
        (payload[0], payload[1]) = split(_rid);

        starknet.sendMessageToL2{value: msg.value}(guest, CAGE, payload);
    }

    function exitPayload(
        uint256 usr, uint256 wad, address sender
    ) internal pure returns (uint256[] memory) {

        uint256[] memory payload = new uint256[](5);
        (payload[0], payload[1]) = split(usr);
        (payload[2], payload[3]) = split(wad);
        payload[4] = uint256(uint160(sender)); // cancelation access control
        return payload;
    }

    function exit(uint256 usr, uint256 wad) external payable validL2Address(usr) {

        _exit(bytes32(usr), wad);

        starknet.sendMessageToL2{value: msg.value}(
            guest, EXIT, exitPayload(usr, wad, msg.sender)
        );
    }

    // TODO: add auth?
    function startUndoExit(uint256 usr, uint256 wad, uint256 nonce) internal {
        starknet.startL1ToL2MessageCancellation(
            guest, EXIT, exitPayload(usr, wad, msg.sender), nonce
        );
    }

    function undoExit(
        address originalSender, uint256 usr, uint256 wad, uint256 nonce
    ) internal {

        starknet.cancelL1ToL2Message(
            guest, EXIT, exitPayload(usr, wad, msg.sender), nonce
        );
        _undoExit(originalSender, bytes32(usr), wad);
    }

    // TODO: data availability???
    function initializeRegisterMint(TeleportGUID calldata teleport) external payable {

        _initializeRegisterMint(teleport);

        uint256[] memory payload = new uint256[](9);
        (payload[0], payload[1]) = split(uint256(teleport.sourceDomain));
        (payload[2], payload[3]) = split(uint256(teleport.targetDomain));
        payload[4] = uint256(teleport.receiver);
        payload[5] = uint256(teleport.operator);
        payload[6] = uint256(teleport.amount);
        payload[7] = uint256(teleport.nonce);
        payload[8] = uint256(teleport.timestamp);

        starknet.sendMessageToL2{value: msg.value}(guest, INITIALIZE_REGISTER_MINT, payload);
    }

    function settlePayload(
        bytes32 sourceDomain, bytes32 targetDomain, uint256 amount
    ) internal pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](6);
        (payload[0], payload[1]) = split(uint256(sourceDomain));
        (payload[2], payload[3]) = split(uint256(targetDomain));
        (payload[4], payload[5]) = split(amount);
        return payload;
    }

    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) external payable {

        uint256 amount = _initializeSettle(sourceDomain, targetDomain);

        starknet.sendMessageToL2{value: msg.value}(
            guest,
            INITIALIZE_SETTLE,
            settlePayload(sourceDomain, targetDomain, amount)
        );
    }

    // TODO: add auth?
    function startUndoInitializeSettle(
        bytes32 sourceDomain, bytes32 targetDomain, uint256 amount, uint256 nonce
    ) external {
        starknet.startL1ToL2MessageCancellation(
            guest,
            INITIALIZE_SETTLE,
            settlePayload(sourceDomain, targetDomain, amount),
            nonce
        );
    }

    function undoInitializeSettle(
        bytes32 sourceDomain, bytes32 targetDomain, uint256 amount, uint256 nonce
    ) external {
        starknet.cancelL1ToL2Message(
            guest,
            INITIALIZE_SETTLE,
            settlePayload(sourceDomain, targetDomain, amount),
            nonce
        );

        _undoInitializeSettle(sourceDomain, targetDomain, amount);
    }

    function release(uint256 _lid, uint256 wad) external {

        _release(_lid, wad);

        uint256[] memory payload = new uint256[](5);
        payload[0] = RELEASE;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(wad);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function surplus(uint256 _lid, uint256 wad) external {

        _surplus(_lid, wad);

        uint256[] memory payload = new uint256[](5);
        payload[0] = SURPLUS;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(wad);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function deficit(uint256 _lid, uint256 wad) external {

        _deficit(_lid, wad);

        uint256[] memory payload = new uint256[](5);
        payload[0] = DEFICIT;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(wad);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function tell(uint256 _lid, uint256 value) external ordered(_lid) {

        _tell(_lid, value);

        uint256[] memory payload = new uint256[](5);
        payload[0] = TELL;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(value);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function finalizeRegisterMint(TeleportGUID calldata teleport) external {

        _finalizeRegisterMint(teleport);
        uint256[] memory payload = new uint256[](10);
        payload[0] = REGISTER_MINT;
        (payload[1], payload[2]) = split(uint256(teleport.sourceDomain));
        (payload[3], payload[4]) = split(uint256(teleport.targetDomain));
        payload[5] = uint256(teleport.receiver);
        payload[6] = uint256(teleport.operator);
        payload[7] = uint256(teleport.amount);
        payload[8] = uint256(teleport.nonce);
        payload[9] = uint256(teleport.timestamp);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function finalizeSettle(
        bytes32 sourceDomain, bytes32 targetDomain, uint256 amount
    ) external {

        _finalizeSettle(sourceDomain, targetDomain, amount);

        uint256[] memory payload = new uint256[](7);
        payload[0] = FINALIZE_SETTLE;
        (payload[1], payload[2]) = split(uint256(sourceDomain));
        (payload[3], payload[4]) = split(uint256(targetDomain));
        (payload[5], payload[6]) = split(amount);

        starknet.consumeMessageFromL2(guest, payload);
    }

    function split(uint256 value) internal pure returns (uint256, uint256) {
      return (value & ((1 << 128) - 1), value >> 128);
    }

    modifier validL2Address(uint256 l2Address) {
        require(l2Address != 0 && l2Address < SN_PRIME, "StarknetDomainHost/invalid-address");
        _;
    }

}
