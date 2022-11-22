// SPDX-License-Identifier: AGPL-3.0-or-later

/// ArbitrumDomainGuest.sol -- DomainGuest for Arbitrum

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

import {DomainGuest,DomainHostLike,TeleportGUID} from "../../DomainGuest.sol";

interface ArbSysLike {
    function sendTxToL1(address target, bytes calldata message) external;
}

contract ArbitrumDomainGuest is DomainGuest {

    // --- Data ---
    ArbSysLike public immutable arbSys;
    address public immutable host;

    uint160 constant OFFSET = uint160(0x1111000000000000000000000000000000001111);

    constructor(
        address _daiJoin,
        address _claimToken,
        address _router,
        address _arbSys,
        address _host
    ) DomainGuest(_daiJoin, _claimToken, _router) {
        arbSys = ArbSysLike(_arbSys);
        host = _host;
    }

    function _isHost(address usr) internal override view returns (bool) {
        unchecked {
            return usr == address(uint160(host) + OFFSET);
        }
    }

    function withdraw(address to, uint256 amount) external {
        _withdraw(to, amount);
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.withdraw.selector, to, amount)
        );
    }

    function release() external {
        (uint256 _rid, uint256 _burned) = _release();
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.release.selector, _rid, _burned)
        );
    }

    function push() external {
        (uint256 _rid, int256 _surplus) = _push();
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.push.selector, _rid, _surplus)
        );
    }

    function tell() external {
        (uint256 _rid, uint256 _cure) = _tell();
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.tell.selector, _rid, _cure)
        );
    }

    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        _initializeRegisterMint(teleport);
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.finalizeRegisterMint.selector, teleport)
        );
    }

    function initializeSettle(uint256 index) external {
        (bytes32 _sourceDomain, bytes32 _targetDomain, uint256 _amount) = _initializeSettle(index);
        arbSys.sendTxToL1(
            host,
            abi.encodeWithSelector(DomainHostLike.finalizeSettle.selector, _sourceDomain, _targetDomain, _amount)
        );
    }

}
