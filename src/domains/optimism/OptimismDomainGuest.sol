// SPDX-License-Identifier: AGPL-3.0-or-later

/// OptimismDomainGuest.sol -- DomainGuest for Optimism

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

interface L2MessengerLike {
    function sendMessage(address target, bytes calldata message, uint32 gasLimit) external;
    function xDomainMessageSender() external view returns (address);
}

contract OptimismDomainGuest is DomainGuest {

    // --- Data ---
    L2MessengerLike public immutable l2messenger;
    address public immutable host;

    uint32 public glRelease;
    uint32 public glPush;
    uint32 public glTell;
    uint32 public glWithdraw;
    uint32 public glFlush;
    uint32 public glInitializeRegisterMint;
    uint32 public glInitializeSettle;

    // --- Events ---
    event FileGL(bytes32 indexed what, uint32 data);

    constructor(
        address _daiJoin,
        address _claimToken,
        address _router,
        address _l2messenger,
        address _host
    ) DomainGuest(_daiJoin, _claimToken, _router) {
        l2messenger = L2MessengerLike(_l2messenger);
        host = _host;
    }

    function filegl(bytes32 what, uint32 data) external auth {
        if (what == "glRelease") glRelease = data;
        else if (what == "glPush") glPush = data;
        else if (what == "glTell") glTell = data;
        else if (what == "glWithdraw") glWithdraw = data;
        else if (what == "glFlush") glFlush = data;
        else if (what == "glInitializeRegisterMint") glInitializeRegisterMint = data;
        else if (what == "glInitializeSettle") glInitializeSettle = data;
        else revert("OptimismDomainGuest/file-unrecognized-param");
        emit FileGL(what, data);
    }

    function _isHost(address usr) internal override view returns (bool) {
        return usr == address(l2messenger) && l2messenger.xDomainMessageSender() == host;
    }

    function withdraw(address to, uint256 amount) external {
        withdraw(to, amount, glWithdraw);
    }
    function withdraw(address to, uint256 amount, uint32 gasLimit) public {
        _withdraw(to, amount);
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.withdraw.selector, to, amount),
            gasLimit
        );
    }

    function release() external {
        release(glRelease);
    }
    function release(uint32 gasLimit) public {
        (uint256 _rid, uint256 _burned) = _release();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.release.selector, _rid, _burned),
            gasLimit
        );
    }

    function push() external {
        push(glPush);
    }
    function push(uint32 gasLimit) public {
        (uint256 _rid, int256 _surplus) = _push();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.push.selector, _rid, _surplus),
            gasLimit
        );
    }

    function tell() external {
        tell(glTell);
    }
    function tell(uint32 gasLimit) public {
        (uint256 _rid, uint256 _cure) = _tell();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.tell.selector, _rid, _cure),
            gasLimit
        );
    }

    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        initializeRegisterMint(teleport, glInitializeRegisterMint);
    }
    function initializeRegisterMint(TeleportGUID calldata teleport, uint32 gasLimit) public {
        _initializeRegisterMint(teleport);
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.finalizeRegisterMint.selector, teleport),
            gasLimit
        );
    }

    function initializeSettle(uint256 index) external {
        initializeSettle(index, glInitializeSettle);
    }
    function initializeSettle(uint256 index, uint32 gasLimit) public {
        (bytes32 _sourceDomain, bytes32 _targetDomain, uint256 _amount) = _initializeSettle(index);
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.finalizeSettle.selector, _sourceDomain, _targetDomain, _amount),
            gasLimit
        );
    }

}
