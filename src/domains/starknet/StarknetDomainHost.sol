// SPDX-License-Identifier: AGPL-3.0-or-later

/// OptimismDomainHost.sol -- DomainHost for Optimism

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

import {DomainHost,DomainGuestLike,Settlement,TeleportGUID} from "../../DomainHost.sol";

interface StarkNetLike {
    function sendMessageToL2(
        uint256 to,
        uint256 selector,
        uint256[] calldata payload
    ) external payable returns (bytes32);

    function consumeMessageFromL2(
        uint256 from,
        uint256[] calldata payload
    ) external returns (bytes32);

    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external;

    function cancelL1ToL2Message(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external;
}

contract StarknetDomainHost is DomainHost {


    // src/starkware/cairo/lang/cairo_constants.py
    //  2 ** 251 + 17 * 2 ** 192 + 1;
    uint256 constant SN_PRIME =
        3618502788666131213697322783095070105623107215331596699973092056135872020481;

    // l1->l2 selectors
    //  from starkware.starknet.compiler.compile import get_selector_from_name
    //  print(get_selector_from_name('deposit'))
    uint256 constant DEPOSIT                  = 1; // TODO
    uint256 constant LIFT                     = 1; // TODO
    uint256 constant RECTIFY                  = 1; // TODO
    uint256 constant CAGE                     = 1; // TODO
    uint256 constant EXIT                     = 1; // TODO
    uint256 constant INITIALIZE_REGISTER_MINT = 1; // TODO
    uint256 constant INITIALIZE_SETTLE        = 1; // TODO

    // l2->l1 selectors
    uint256 constant WITHDRAW        = 1;
    uint256 constant RELEASE         = 2;
    uint256 constant PUSH            = 3;
    uint256 constant TELL            = 4;
    uint256 constant REGISTER_MINT   = 5;
    uint256 constant FINALIZE_SETTLE = 6;

    // --- Data ---
    StarkNetLike public immutable starkNet;
    uint256 public immutable l2Dai;
    uint256 public immutable guest;

    constructor(
        bytes32 _ilk,
        address _daiJoin,
        address _escrow,
        address _router,
        address _starkNet,
        uint256 _guest,
        uint256 _l2Dai
    ) DomainHost(_ilk, _daiJoin, _escrow, _router) {
        starkNet = StarkNetLike(_starkNet);
        guest = _guest;
        l2Dai = _l2Dai;
    }

    // TODO: not compatible with starkgate!

    function depositPayload(uint256 to, uint256 amount, address sender) private returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](4);
        payload[0] = to;
        (payload[1], payload[2]) = split(amount);
        payload[3] = uint256(uint160(sender)); // deposit cancelation access control

        return payload;
    }

    function deposit(uint256 to, uint256 amount) external payable validL2Address(to) {
        (uint256 _to, uint256 _amount) = _deposit(to, amount);
        require(_to != l2Dai, "StarknetDomainHost/invalid-address");

        starkNet.sendMessageToL2{value: msg.value}(
            guest, DEPOSIT, depositPayload(_to, _amount, msg.sender)
        );
    }

    function startUndoDeposit(uint256 to, uint256 amount, uint256 nonce) internal {
        starkNet.startL1ToL2MessageCancellation(
            guest, DEPOSIT, depositPayload(to, amount, msg.sender), nonce
        );
    }

    function undoDeposit(
        address originalSender, uint256 to, uint256 amount, uint256 nonce
    ) internal {
        starkNet.cancelL1ToL2Message(
            guest, DEPOSIT, depositPayload(to, amount, msg.sender), nonce
        );
        _undoDeposit(originalSender, amount);
    }

    // TODO: compatibility with Starkgate
    function withdraw(address to, uint256 amount) external {
        _withdraw(to, amount);

        uint256[] memory payload = new uint256[](4);
        payload[0] = WITHDRAW;
        payload[1] = uint256(uint160(to)); // TODO: change versus v1, verify l2 implementation
        (payload[2], payload[3]) = split(amount);

        starkNet.consumeMessageFromL2(guest, payload);
    }

    function lift(uint256 wad) external payable {
        (uint256 _rid, uint256 _wad) = _lift(wad);
        uint256[] memory payload = new uint256[](4);
        (payload[0], payload[1]) = split(_rid);
        (payload[2], payload[3]) = split(_wad);

        starkNet.sendMessageToL2{value: msg.value}(guest, LIFT, payload);
    }

    function rectify() external payable {
        (uint256 _rid, uint256 _wad) = _rectify();
        uint256[] memory payload = new uint256[](4);
        (payload[0], payload[1]) = split(_rid);
        (payload[2], payload[3]) = split(_wad);

        starkNet.sendMessageToL2{value: msg.value}(guest, RECTIFY, payload);
    }

    function cage() external payable {
        (uint256 _rid) = _cage();
        uint256[] memory payload = new uint256[](2);
        (payload[0], payload[1]) = split(_rid);

        starkNet.sendMessageToL2{value: msg.value}(guest, CAGE, payload);
    }

    function exitPayload(
        uint256 usr, uint256 wad, address sender
    ) internal pure returns (uint256[] memory) {
        uint256[] memory payload = new uint256[](4);
        (payload[0], payload[1]) = split(usr);
        (payload[2], payload[3]) = split(wad);
        payload[4] = uint256(uint160(sender)); // cancelation access control
        return payload;
    }

    function exit(uint256 usr, uint256 wad) external payable validL2Address(usr) {

        (uint256 _usr, uint256 _wad) = _exit(usr, wad);

        starkNet.sendMessageToL2{value: msg.value}(
            guest, EXIT, exitPayload(_usr, _wad, msg.sender)
        );
    }

    function startUndoExit(uint256 usr, uint256 wad, uint256 nonce) internal {
        StarkNetLike(starkNet).startL1ToL2MessageCancellation(
            guest, EXIT, exitPayload(usr, wad, msg.sender), nonce
        );
    }

    function undoExit(
        address originalSender, uint256 usr, uint256 wad, uint256 nonce
    ) internal {
        StarkNetLike(starkNet).cancelL1ToL2Message(
            guest, EXIT, exitPayload(usr, wad, msg.sender), nonce
        );
        _undoExit(originalSender, wad);
    }

    // TODO: data availability???
    function initializeRegisterMint(TeleportGUID calldata teleport) external payable {

        (TeleportGUID calldata _teleport) = _initializeRegisterMint(teleport);

        uint256[] memory payload = new uint256[](10);
        (payload[0], payload[1]) = split(uint256(teleport.sourceDomain));
        (payload[2], payload[3]) = split(uint256(teleport.targetDomain));
        payload[4] = uint256(teleport.receiver);
        payload[5] = uint256(teleport.operator);
        payload[6] = uint256(teleport.amount);
        payload[7] = uint256(teleport.nonce);
        payload[8] = uint256(teleport.timestamp);

        starkNet.sendMessageToL2{value: msg.value}(guest, INITIALIZE_REGISTER_MINT, payload);
    }

    function initializeSettle(uint256 index) external payable {
        (bytes32 _sourceDomain, bytes32 _targetDomain, uint256 _amount) = _initializeSettle(index);

        uint256[] memory payload = new uint256[](6);
        (payload[0], payload[1]) = split(uint256(_sourceDomain));
        (payload[2], payload[3]) = split(uint256(_targetDomain));
        (payload[4], payload[5]) = split(_amount);

        starkNet.sendMessageToL2{value: msg.value}(guest, INITIALIZE_SETTLE, payload);
    }

    function startUndoInitializeSettle(uint256 index, uint256 nonce) external {
        Settlement memory settlement = settlementQueue[index];
        require(!settlement.sent, "DomainHost/settlement-already-sent");

        uint256[] memory payload = new uint256[](6);
        (payload[0], payload[1]) = split(uint256(settlement.sourceDomain));
        (payload[2], payload[3]) = split(uint256(settlement.targetDomain));
        (payload[4], payload[5]) = split(settlement.amount);

        StarkNetLike(starkNet).startL1ToL2MessageCancellation(
            guest, INITIALIZE_SETTLE, payload, nonce
        );
    }

    function undoInitializeSettle(uint256 index, uint256 nonce) external {
        Settlement memory settlement = settlementQueue[index];
        require(!settlement.sent, "DomainHost/settlement-already-sent");

        uint256[] memory payload = new uint256[](6);
        (payload[0], payload[1]) = split(uint256(settlement.sourceDomain));
        (payload[2], payload[3]) = split(uint256(settlement.targetDomain));
        (payload[4], payload[5]) = split(settlement.amount);

        StarkNetLike(starkNet).cancelL1ToL2Message(guest, INITIALIZE_SETTLE, payload, nonce);

        _undoInitializeSettle(index);
    }

    function release(uint256 _lid, uint256 wad) external {
        _release(_lid, wad);

        uint256[] memory payload = new uint256[](5);
        payload[0] = RELEASE;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(wad);

        starkNet.consumeMessageFromL2(guest, payload);
    }

    function push(uint256 _lid, int256 wad) external {
        _push(_lid, wad);

        uint256[] memory payload = new uint256[](5);
        payload[0] = PUSH;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(uint256(wad));

        starkNet.consumeMessageFromL2(guest, payload);
    }

    function tell(uint256 _lid, uint256 value) external ordered(_lid) {
        _tell(_lid, value);

        uint256[] memory payload = new uint256[](5);
        payload[0] = TELL;
        (payload[1], payload[2]) = split(_lid);
        (payload[3], payload[4]) = split(value);

        starkNet.consumeMessageFromL2(guest, payload);
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

        starkNet.consumeMessageFromL2(guest, payload);
    }

    function finalizeSettle(
        bytes32 sourceDomain, bytes32 targetDomain, uint256 amount
    ) external {
        _finalizeSettle(sourceDomain, targetDomain, amount);

        uint256[] memory payload = new uint256[](5);
        payload[0] = FINALIZE_SETTLE;
        (payload[1], payload[2]) = split(uint256(sourceDomain));
        (payload[3], payload[4]) = split(uint256(targetDomain));
        (payload[5], payload[6]) = split(amount);

        starkNet.consumeMessageFromL2(guest, payload);
    }

    function split(uint256 value) internal pure returns (uint256, uint256) {
      return (value & ((1 << 128) - 1), value >> 128);
    }

    modifier validL2Address(uint256 l2Address) {
        require(l2Address != 0 && l2Address < SN_PRIME, "StarknetDomainHost/invalid-address");
        _;
    }
}
