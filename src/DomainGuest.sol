// SPDX-License-Identifier: AGPL-3.0-or-later

/// DomainGuest.sol -- xdomain guest dss manager

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

interface DomainHostLike {
    function withdraw(address to, uint256 amount) external;
    function release(uint256 _lid, uint256 wad) external;
    function push(uint256 _lid, int256 wad) external;
    function tell(uint256 _lid, uint256 value) external;
    function finalizeRegisterMint(TeleportGUID calldata teleport) external;
    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external;
}

interface VatLike {
    function hope(address usr) external;
    function debt() external view returns (uint256);
    function Line() external view returns (uint256);
    function file(bytes32 what, uint256 data) external;
    function dai(address usr) external view returns (uint256);
    function sin(address usr) external view returns (uint256);
    function heal(uint256 rad) external;
    function swell(address u, int256 rad) external;
}

interface TokenLike {
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function approve(address usr, uint wad) external returns (bool);
    function mint(address to, uint256 value) external;
}

interface DaiJoinLike {
    function vat() external view returns (VatLike);
    function dai() external view returns (TokenLike);
    function join(address usr, uint256 wad) external;
    function exit(address usr, uint256 wad) external;
}

interface EndLike {
    function cage() external;
    function debt() external view returns (uint256);
}

interface RouterLike {
    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external;
    function registerMint(TeleportGUID calldata teleport) external;
}

struct Settlement {
    bytes32 sourceDomain;
    bytes32 targetDomain;
    uint256 amount;
    bool    sent;
}

/// @title Support for xchain MCD, canonical DAI and Maker Teleport - guest instance
/// @dev This is just the business logic which needs concrete message-passing implementation
abstract contract DomainGuest {
    
    // --- Data ---
    mapping (address => uint256) public wards;
    mapping (bytes32 => bool)    public teleports;
    Settlement[]                 public settlementQueue;

    EndLike public end;
    uint256 public lid;         // Local ordering id
    uint256 public rid;         // Remote ordering id
    uint256 public grain;       // Keep track of the pre-minted DAI in the remote escrow [WAD]
    uint256 public live;
    uint256 public dust;        // The dust limit for preventing spam attacks [RAD]

    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;
    TokenLike   public immutable dai;
    TokenLike   public immutable claimToken;
    RouterLike  public immutable router;

    uint256 constant RAY = 10 ** 27;

    string constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);
    event Lift(uint256 wad);
    event Release(uint256 burned);
    event Push(int256 surplus);
    event Rectify(uint256 wad);
    event Cage();
    event Tell(uint256 value);
    event Exit(address indexed usr, uint256 wad);
    event Deposit(address indexed to, uint256 amount);
    event Withdraw(address indexed sender, address indexed to, uint256 amount);
    event RegisterMint(TeleportGUID teleport);
    event InitializeRegisterMint(TeleportGUID teleport);
    event FinalizeRegisterMint(TeleportGUID teleport);
    event Settle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event InitializeSettle(uint256 index, bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event FinalizeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);

    modifier auth {
        require(wards[msg.sender] == 1, "DomainGuest/not-authorized");
        _;
    }

    function _isHost(address usr) internal virtual view returns (bool);
    modifier hostOnly {
        require(_isHost(msg.sender), "DomainGuest/not-host");
        _;
    }

    modifier ordered(uint256 _lid) {
        require(lid++ == _lid, "DomainGuest/out-of-order");
        _;
    }

    constructor(address _daiJoin, address _claimToken, address _router) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        daiJoin = DaiJoinLike(_daiJoin);
        vat = daiJoin.vat();
        dai = daiJoin.dai();
        claimToken = TokenLike(_claimToken);
        router = RouterLike(_router);

        vat.hope(_daiJoin);
        dai.approve(_daiJoin, type(uint256).max);
        dai.approve(_router, type(uint256).max);

        live = 1;
    }

    // --- Math ---
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "end") end = EndLike(data);
        else revert("DomainGuest/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "dust") dust = data;
        else revert("DomainGuest/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Canonical DAI Support ---

    /// @notice Mint DAI and send to user
    /// @param to The address to send the DAI to on the local domain
    /// @param amount The amount of DAI to send [WAD]
    function deposit(address to, uint256 amount) external hostOnly {
        vat.swell(address(this), _int256(amount * RAY));
        daiJoin.exit(to, amount);

        emit Deposit(to, amount);
    }

    /// @notice Withdraw DAI by burning local canonical DAI
    /// @param to The address to send the DAI to on the remote domain
    /// @param amount The amount of DAI to withdraw [WAD]
    function _withdraw(address to, uint256 amount) internal returns (address _to, uint256 _amount) {
        require(dai.transferFrom(msg.sender, address(this), amount), "DomainGuest/transfer-failed");
        daiJoin.join(address(this), amount);
        vat.swell(address(this), -_int256(amount * RAY));

        _to = to;
        _amount = amount;

        emit Withdraw(msg.sender, to, amount);
    }

    // --- MCD Support ---

    /// @notice Record changes in line and grain and update dss global debt ceiling if necessary
    /// @param _lid Local ordering id
    /// @param wad The new debt ceiling [WAD]
    function lift(uint256 _lid, uint256 wad) external hostOnly ordered(_lid) {
        require(live == 1, "DomainGuest/not-live");

        uint256 lastLine = vat.Line();
        uint256 rad = wad * RAY;
        if (rad > lastLine) grain = wad;
        vat.file("Line", rad);

        emit Lift(wad);
    }

    /// @notice Will release remote DAI from the escrow when it is safe to do so
    /// @dev    Should be run by keeper on a regular schedule.
    function _release() internal returns (uint256 _rid, uint256 _burned) {
        require(live == 1, "DomainGuest/not-live");

        uint256 limit = _max(vat.Line() / RAY, _divup(vat.debt(), RAY));
        require(grain >= limit + dust / RAY, "DomainGuest/dust");
        uint256 burned = grain - limit;
        grain = limit;

        _rid = rid++;
        _burned = burned;

        emit Release(burned);
    }

    /// @notice Push surplus (or deficit) to the host dss
    /// @dev Should be run by keeper on a regular schedule
    function _push() internal returns (uint256 _rid, int256 _surplus) {
        require(live == 1, "DomainGuest/not-live");

        _rid = rid++;

        uint256 _dai = vat.dai(address(this));
        uint256 _sin = vat.sin(address(this));
        if (_dai >= _sin + dust) {
            // We have a surplus
            if (_sin > 0) vat.heal(_sin);

            uint256 wad = (_dai - _sin) / RAY;    // Round against this contract for surplus

            // Burn the DAI and unload on the other side
            vat.swell(address(this), -_int256(wad * RAY));
            _surplus = _int256(wad);

            emit Push(int256(wad));
        } else if (_sin >= _dai + dust) {
            // We have a deficit
            if (_dai > 0) vat.heal(_dai);

            int256 deficit = -_int256(_divup(_sin - _dai, RAY));    // Round up to overcharge for deficit
            _surplus = deficit;

            emit Push(deficit);
        } else {
            revert("DomainGuest/dust");
        }
    }

    /// @notice Merge DAI into surplus
    /// @param _lid Local ordering id
    /// @param wad The amount of DAI that has been sent to this domain [WAD]
    function rectify(uint256 _lid, uint256 wad) external hostOnly ordered(_lid) {
        vat.swell(address(this), _int256(wad * RAY));

        emit Rectify(wad);
    }

    /// @notice Trigger the end module
    /// @param _lid Local ordering id
    function cage(uint256 _lid) external hostOnly ordered(_lid) {
        require(live == 1, "DomainGuest/not-live");

        live = 0;
        end.cage();

        emit Cage();
    }

    /// @notice Set the cure value for the host
    /// @dev Triggered during shutdown
    function _tell() internal returns (uint256 _rid, uint256 _cure) {
        uint256 debt = end.debt();
        require(debt > 0 || (vat.debt() == 0 && live == 0), "DomainGuest/end-debt-zero");
        uint256 _grain = grain * RAY;
        uint256 cure = _grain > debt ? _grain - debt : 0;

        _rid = rid++;
        _cure = cure;

        emit Tell(cure);
    }

    /// @notice Transfer a claim token for the given user
    /// @dev    This will transfer a scaled claim from the end.
    /// @param usr The destination to send the claim tokens to
    /// @param wad The amount of claim tokens to mint
    function exit(address usr, uint256 wad) external hostOnly {
        // Convert to actual debt amount
        // Round against the user
        uint256 claimAmount = wad * (end.debt() / grain);

        claimToken.transferFrom(address(end), usr, claimAmount);

        emit Exit(usr, wad);
    }

    function heal(uint256 amount) external {
        vat.heal(amount);
    }
    function heal() external {
        vat.heal(_min(vat.dai(address(this)), vat.sin(address(this))));
    }

    // --- Maker Teleport Support ---
    function registerMint(TeleportGUID calldata teleport) external auth {
        teleports[getGUIDHash(teleport)] = true;

        emit RegisterMint(teleport);
    }
    function _initializeRegisterMint(TeleportGUID calldata teleport) internal returns (TeleportGUID calldata _teleport) {
        // There is no issue with resending these messages as the end TeleportJoin will enforce only-once execution
        require(teleports[getGUIDHash(teleport)], "DomainGuest/teleport-not-registered");

        _teleport = teleport;

        emit InitializeRegisterMint(teleport);
    }
    function finalizeRegisterMint(TeleportGUID calldata teleport) external hostOnly {
        router.registerMint(teleport);

        emit FinalizeRegisterMint(teleport);
    }

    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external auth {
        daiJoin.join(address(this), amount);
        vat.swell(address(this), -_int256(amount * RAY));
        settlementQueue.push(Settlement({
            sourceDomain: sourceDomain,
            targetDomain: targetDomain,
            amount: amount,
            sent: false
        }));

        emit Settle(sourceDomain, targetDomain, amount);
    }
    function _initializeSettle(uint256 index) internal returns (bytes32 _sourceDomain, bytes32 _targetDomain, uint256 _amount) {
        require(index < settlementQueue.length, "DomainGuest/settlement-not-found");
        Settlement memory settlement = settlementQueue[index];
        require(!settlement.sent, "DomainGuest/settlement-already-sent");
        settlementQueue[index].sent = true;

        _sourceDomain = settlement.sourceDomain;
        _targetDomain = settlement.targetDomain;
        _amount = settlement.amount;

        emit InitializeSettle(index, settlement.sourceDomain, settlement.targetDomain, settlement.amount);
    }
    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external hostOnly {
        vat.swell(address(this), _int256(amount * RAY));
        daiJoin.exit(address(this), amount);
        router.settle(sourceDomain, targetDomain, amount);

        emit FinalizeSettle(sourceDomain, targetDomain, amount);
    }

    function settlementQueueCount() external view returns (uint256) {
        return settlementQueue.length;
    }
    
}
