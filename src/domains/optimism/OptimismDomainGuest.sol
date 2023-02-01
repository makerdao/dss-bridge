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

    modifier hostOnly {
        require(msg.sender == address(l2messenger) && l2messenger.xDomainMessageSender() == host, "DomainGuest/not-host");
        _;
    }

    function deposit(address to, uint256 amount) external hostOnly {
        _deposit(to, amount);
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

    function lift(uint256 _lid, uint256 wad) external hostOnly {
        _lift(_lid, wad);
    }

    function surplus() external {
        surplus(glPush);
    }
    function surplus(uint32 gasLimit) public {
        (uint256 _rid, uint256 _wad) = _surplus();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.surplus.selector, _rid, _wad),
            gasLimit
        );
    }

    function deficit() external {
        deficit(glPush);
    }
    function deficit(uint32 gasLimit) public {
        (uint256 _rid, uint256 _wad) = _deficit();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.deficit.selector, _rid, _wad),
            gasLimit
        );
    }

    function rectify(uint256 _lid, uint256 wad) external hostOnly {
        _rectify(_lid, wad);
    }

    function cage(uint256 _lid) external hostOnly {
        _cage(_lid);
    }

    function tell() external {
        tell(glTell);
    }
    function tell(uint32 gasLimit) public {
        (uint256 _rid, uint256 _debt) = _tell();
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.tell.selector, _rid, _debt),
            gasLimit
        );
    }

    function exit(address usr, uint256 wad) external hostOnly {
        _exit(usr, wad);
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

    function finalizeRegisterMint(TeleportGUID calldata teleport) external hostOnly {
        _finalizeRegisterMint(teleport);
    }

    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) external {
        initializeSettle(sourceDomain, targetDomain, glInitializeSettle);
    }
    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint32 gasLimit) public {
        uint256 _amount = _initializeSettle(sourceDomain, targetDomain);
        l2messenger.sendMessage(
            host,
            abi.encodeWithSelector(DomainHostLike.finalizeSettle.selector, sourceDomain, targetDomain, _amount),
            gasLimit
        );
    }

    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external hostOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }

}
