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

import {DomainGuestLike,TeleportGUID} from "../../DomainHost.sol";
import {OptimisticDomainHost} from "../../OptimisticDomainHost.sol";

interface L1MessengerLike {
    function sendMessage(address target, bytes calldata message, uint32 gasLimit) external;
    function xDomainMessageSender() external view returns (address);
}

contract OptimismDomainHost is OptimisticDomainHost {

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
    ) OptimisticDomainHost(_ilk, _daiJoin, _escrow, _router) {
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

    function _isGuest(address usr) internal override view returns (bool) {
        return usr == address(l1messenger) && l1messenger.xDomainMessageSender() == guest;
    }

    function deposit(address to, uint256 amount) external {
        deposit(to, amount, glDeposit);
    }
    function deposit(address to, uint256 amount, uint32 gasLimit) public {
        (address _to, uint256 _amount) = _deposit(to, amount);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.deposit.selector, _to, _amount),
            gasLimit
        );
    }

    function lift(uint256 wad) external {
        lift(wad, glLift);
    }
    function lift(uint256 wad, uint32 gasLimit) public {
        (uint256 _rid, uint256 _wad) = _lift(wad);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.lift.selector, _rid, _wad),
            gasLimit
        );
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
        (uint256 _rid) = _cage();
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.cage.selector, _rid),
            gasLimit
        );
    }

    function exit(address usr, uint256 wad) external {
        exit(usr, wad, glExit);
    }
    function exit(address usr, uint256 wad, uint32 gasLimit) public {
        (address _usr, uint256 _wad) = _exit(usr, wad);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.exit.selector, _usr, _wad),
            gasLimit
        );
    }

    function initializeRegisterMint(TeleportGUID calldata teleport) external {
        initializeRegisterMint(teleport, glInitializeRegisterMint);
    }
    function initializeRegisterMint(TeleportGUID calldata teleport, uint32 gasLimit) public {
        (TeleportGUID calldata _teleport) = _initializeRegisterMint(teleport);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.finalizeRegisterMint.selector, _teleport),
            gasLimit
        );
    }

    function initializeSettle(uint256 index) external {
        initializeSettle(index, glInitializeSettle);
    }
    function initializeSettle(uint256 index, uint32 gasLimit) public {
        (bytes32 _sourceDomain, bytes32 _targetDomain, uint256 _amount) = _initializeSettle(index);
        l1messenger.sendMessage(
            guest,
            abi.encodeWithSelector(DomainGuestLike.finalizeSettle.selector, _sourceDomain, _targetDomain, _amount),
            gasLimit
        );
    }

}
