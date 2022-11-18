// SPDX-License-Identifier: AGPL-3.0-or-later

/// DomainHost.sol -- xdomain host dss credit faciility

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

import "./TeleportGUID.sol";
import "./DomainHost.sol";

abstract contract OptimisticDomainHost is DomainHost {

    function _isGuest(address usr) internal virtual view returns (bool);
    modifier guestOnly {
        require(_isGuest(msg.sender), "DomainHost/not-guest");
        _;
    }

    constructor(
        bytes32 _ilk,
        address _daiJoin,
        address _escrow,
        address _router
    ) DomainHost(_ilk, _daiJoin, _escrow, _router) {
    }

    function withdraw(address to, uint256 amount) external guestOnly {
        _withdraw(to, amount);
    }

    function release(uint256 _lid, uint256 wad) external guestOnly {
        _release(_lid, wad);
    }

    function push(uint256 _lid, int256 wad) external guestOnly {
        _push(_lid, wad);
    }

    function tell(uint256 _lid, uint256 value) external guestOnly {
        _tell(_lid, value);
    }

    function finalizeRegisterMint(TeleportGUID calldata teleport) external guestOnly {
        _finalizeRegisterMint(teleport);
    }

    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external guestOnly {
        _finalizeSettle(sourceDomain, targetDomain, amount);
    }
}
