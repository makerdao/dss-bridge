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

import {DomainHost,DomainGuestLike,TeleportGUID} from "../../DomainHost.sol";

interface L1MessengerLike {
    function sendMessage(address target, bytes calldata message, uint32 gasLimit) external;
    function xDomainMessageSender() external view returns (address);
}

contract OptimismDomainHost is DomainHost {

    // --- Data ---
    L1MessengerLike public immutable l1messenger;
    address public immutable guest;

    uint32 public glLift;
    uint32 public glRectify;
    uint32 public glCage;
    uint32 public glExit;
    uint32 public glDeposit;
    uint32 public glInitializeRegisterMint;
    uint32 public glInitializeSettle;

    // --- Events ---
    event File(bytes32 indexed what, uint32 data);

    constructor(
        bytes32 _ilk,
        address _daiJoin,
        address _escrow,
        address _router,
        address _l1messenger,
        address _guest
    ) DomainHost(_ilk, _daiJoin, _escrow, _router) {
        l1messenger = L1MessengerLike(_l1messenger);
        guest = _guest;
    }

    function file(bytes32 what, uint32 data) external auth {
        if (what == "glLift") glLift = data;
        else if (what == "glRectify") glRectify = data;
        else if (what == "glCage") glCage = data;
        else if (what == "glExit") glExit = data;
        else if (what == "glDeposit") glDeposit = data;
        else if (what == "glInitializeRegisterMint") glInitializeRegisterMint = data;
        else if (what == "glInitializeSettle") glInitializeSettle = data;
        else revert("OptimismDomainHost/file-unrecognized-param");
        emit File(what, data);
    }

    modifier guestOnly {
        require(msg.sender == address(l1messenger) && l1messenger.xDomainMessageSender() == guest, "DomainHost/not-guest");
        _;
    }

    function deposit(address to, uint256 amount) external {
        deposit(to, amount, glDeposit);
    }
    function deposit(address to, uint256 amount, uint32 gasLimit) public {
        _deposit(to, amount);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.deposit.selector, to, amount),
            gasLimit
        );
    }

    function withdraw(address to, uint256 amount) external guestOnly {
        _withdraw(to, amount);
    }

    function lift(uint256 wad) external {
        lift(wad, glLift);
    }
    function lift(uint256 wad, uint32 gasLimit) public {
        uint256 _rid = _lift(wad);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.lift.selector, _rid, wad),
            gasLimit
        );
    }

    function surplus(uint256 _lid, uint256 wad) external guestOnly {
        _surplus(_lid, wad);
    }

    function deficit(uint256 _lid, uint256 wad) external guestOnly {
        _deficit(_lid, wad);
    }

    function rectify() external {
        rectify(glRectify);
    }
    function rectify(uint32 gasLimit) public {
        (uint256 _rid, uint256 _wad) = _rectify();
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.rectify.selector, _rid, _wad),
            gasLimit
        );
    }

    function cage() external {
        cage(glCage);
    }
    function cage(uint32 gasLimit) public {
        uint256 _rid = _cage();
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.cage.selector, _rid),
            gasLimit
        );
    }

    function tell(uint256 _lid, uint256 debt) external guestOnly {
        _tell(_lid, debt);
    }

    function exit(address usr, uint256 wad) external {
        exit(usr, wad, glExit);
    }
    function exit(address usr, uint256 wad, uint32 gasLimit) public {
        uint256 claim = _exit(usr, wad);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.exit.selector, usr, claim),
            gasLimit
        );
    }

    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        initializeRegisterMint(teleport, glInitializeRegisterMint);
    }
    function initializeRegisterMint(TeleportGUID calldata teleport, uint32 gasLimit) public {
        _initializeRegisterMint(teleport);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.finalizeRegisterMint.selector, teleport),
            gasLimit
        );
    }

    function finalizeRegisterMint(TeleportGUID calldata teleport) external guestOnly {
        _finalizeRegisterMint(teleport);
    }

    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) external {
        initializeSettle(sourceDomain, targetDomain, glInitializeSettle);
    }
    function initializeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint32 gasLimit) public {
        uint256 _amount = _initializeSettle(sourceDomain, targetDomain);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.finalizeSettle.selector, sourceDomain, targetDomain, _amount),
            gasLimit
        );
    }

    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external guestOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }

}
