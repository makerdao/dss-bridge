// SPDX-License-Identifier: AGPL-3.0-or-later

/// ArbitrumDomainHost.sol -- DomainHost for Arbitrum

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

interface InboxLike {
    function createRetryableTicket(
        address destAddr,
        uint256 arbTxCallValue,
        uint256 maxSubmissionCost,
        address submissionRefundAddress,
        address valueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable returns (uint256);
    function bridge() external view returns (address);
}

interface BridgeLike {
    function activeOutbox() external view returns (address);
}

interface OutboxLike {
    function l2ToL1Sender() external view returns (address);
}

contract ArbitrumDomainHost is DomainHost {

    // --- Data ---
    InboxLike public immutable inbox;
    address public immutable guest;

    uint256 public glLift;
    uint256 public glRectify;
    uint256 public glCage;
    uint256 public glExit;
    uint256 public glDeposit;
    uint256 public glInitializeRegisterMint;
    uint256 public glInitializeSettle;

    // --- Events ---
    event File(bytes32 indexed what, uint256 data);

    constructor(
        bytes32 _ilk,
        address _daiJoin,
        address _escrow,
        address _router,
        address _inbox,
        address _guest
    ) DomainHost(_ilk, _daiJoin, _escrow, _router) {
        inbox = InboxLike(_inbox);
        guest = _guest;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "glLift") glLift = data;
        else if (what == "glRectify") glRectify = data;
        else if (what == "glCage") glCage = data;
        else if (what == "glExit") glExit = data;
        else if (what == "glDeposit") glDeposit = data;
        else if (what == "glInitializeRegisterMint") glInitializeRegisterMint = data;
        else if (what == "glInitializeSettle") glInitializeSettle = data;
        else revert("ArbitrumDomainHost/file-unrecognized-param");
        emit File(what, data);
    }

    modifier guestOnly {
        address bridge = inbox.bridge();
        require(msg.sender == bridge && guest == OutboxLike(BridgeLike(bridge).activeOutbox()).l2ToL1Sender(), "DomainHost/not-guest");
        _;
    }

    function deposit(
        address to,
        uint256 amount,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        _deposit(to, amount);
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            abi.encodeWithSelector(DomainGuestLike.deposit.selector, to, amount)
        );
    }
    function deposit(
        address to,
        uint256 amount,
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        deposit(
            to,
            amount,
            maxSubmissionCost,
            glDeposit,
            gasPriceBid
        );
    }

    function withdraw(address to, uint256 amount) external guestOnly {
        _withdraw(to, amount);
    }

    function lift(
        uint256 wad,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        (uint256 _rid, uint256 rad) = _lift(wad);
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            // Needed to inline _lift(wad) here because of stack too deep
            abi.encodeWithSelector(DomainGuestLike.lift.selector, _rid, rad)
        );
    }
    function lift(
        uint256 wad,
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        lift(
            wad,
            maxSubmissionCost,
            glLift,
            gasPriceBid
        );
    }

    function surplus(uint256 _lid, uint256 wad) external guestOnly {
        _surplus(_lid, wad);
    }

    function deficit(uint256 _lid, uint256 wad) external guestOnly {
        _deficit(_lid, wad);
    }

    function rectify(
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        (uint256 _rid, uint256 _wad) = _rectify();
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            abi.encodeWithSelector(DomainGuestLike.rectify.selector, _rid, _wad)
        );
    }
    function rectify(
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        rectify(
            maxSubmissionCost,
            glLift,
            gasPriceBid
        );
    }

    function cage(
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        uint256 _rid = _cage();
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            abi.encodeWithSelector(DomainGuestLike.cage.selector, _rid)
        );
    }
    function cage(
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        cage(
            maxSubmissionCost,
            glCage,
            gasPriceBid
        );
    }

    function tell(uint256 _lid, uint256 debt) external guestOnly {
        _tell(_lid, debt);
    }

    function exit(
        address usr,
        uint256 wad,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        bytes memory data = abi.encodeWithSelector(DomainGuestLike.exit.selector, usr, _exit(usr, wad)); // Needed to inline _exit(usr, wad) here because of stack too deep
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            data
        );
    }
    function exit(
        address usr,
        uint256 wad,
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        exit(
            usr,
            wad,
            maxSubmissionCost,
            glExit,
            gasPriceBid
        );
    }

    function initializeRegisterMint(
        TeleportGUID calldata teleport,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        _initializeRegisterMint(teleport);
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            abi.encodeWithSelector(DomainGuestLike.finalizeRegisterMint.selector, teleport)
        );
    }
    function initializeRegisterMint(
        TeleportGUID calldata teleport,
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        initializeRegisterMint(
            teleport,
            maxSubmissionCost,
            glInitializeRegisterMint,
            gasPriceBid
        );
    }

    function finalizeRegisterMint(TeleportGUID calldata teleport) external guestOnly {
        _finalizeRegisterMint(teleport);
    }

    function initializeSettle(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    ) public payable {
        uint256 _amount = _initializeSettle(sourceDomain, targetDomain);
        bytes memory data = abi.encodeWithSelector(DomainGuestLike.finalizeSettle.selector, sourceDomain, targetDomain, _amount);
        inbox.createRetryableTicket{value: msg.value}(
            guest,
            0, // we always assume that l2CallValue = 0
            maxSubmissionCost,
            msg.sender,
            msg.sender,
            maxGas,
            gasPriceBid,
            data
        );
    }
    function initializeSettle(
        bytes32 sourceDomain,
        bytes32 targetDomain,
        uint256 maxSubmissionCost,
        uint256 gasPriceBid
    ) external payable {
        initializeSettle(
            sourceDomain,
            targetDomain,
            maxSubmissionCost,
            glDeposit,
            gasPriceBid
        );
    }

    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external guestOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }

}
