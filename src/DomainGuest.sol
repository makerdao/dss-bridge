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
    function surplus(uint256 _lid, uint256 wad) external;
    function deficit(uint256 _lid, uint256 wad) external;
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

/// @title Support for xchain MCD, canonical DAI and Maker Teleport - guest instance
/// @dev This is just the business logic which needs concrete message-passing implementation
abstract contract DomainGuest {
    
    // --- Data ---
    mapping (address => uint256) public wards;
    mapping (bytes32 => bool)    public teleports;
    mapping (bytes32 => mapping (bytes32 => uint256)) public settlements;

    EndLike public end;
    uint256 public lid;         // Local ordering id
    uint256 public rid;         // Remote ordering id
    uint256 public dsin;        // Amount already requested to parent domain to re-capitalize this one but hasn't yet been paid [WAD]
    uint256 public live;
    uint256 public dust;        // The dust limit for preventing spam attacks [WAD]

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
    event Lift(uint256 rad);
    event Surplus(uint256 wad);
    event Deficit(uint256 wad);
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
    event InitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event FinalizeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);

    modifier auth {
        require(wards[msg.sender] == 1, "DomainGuest/not-authorized");
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
        if (what == "lid") lid = data;
        else if (what == "rid") rid = data;
        else if (what == "dsin") dsin = data;
        else if (what == "dust") dust = data;
        else revert("DomainGuest/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Canonical DAI Support ---

    /// @notice Mint DAI and send to user
    /// @param to The address to send the DAI to on the local domain
    /// @param amount The amount of DAI to send [WAD]
    function _deposit(address to, uint256 amount) internal {
        vat.swell(address(this), _int256(amount * RAY));
        daiJoin.exit(to, amount);

        emit Deposit(to, amount);
    }

    /// @notice Withdraw DAI by burning local canonical DAI
    /// @param to The address to send the DAI to on the remote domain
    /// @param amount The amount of DAI to withdraw [WAD]
    function _withdraw(address to, uint256 amount) internal {
        dai.transferFrom(msg.sender, address(this), amount);
        daiJoin.join(address(this), amount);
        vat.swell(address(this), -_int256(amount * RAY));

        emit Withdraw(msg.sender, to, amount);
    }

    // --- MCD Support ---

    /// @notice Record changes in Line
    /// @param _lid Local ordering id
    /// @param rad The new debt ceiling [RAD]
    function _lift(uint256 _lid, uint256 rad) internal ordered(_lid) {
        require(live == 1, "DomainGuest/not-live");

        vat.file("Line", rad);

        emit Lift(rad);
    }

    /// @notice Push surplus to the host dss
    /// @dev Should be run by keeper on a regular schedule
    function _surplus() internal returns (uint256 _rid, uint256 wad) {
        require(live == 1, "DomainGuest/not-live");

        _rid = rid++;

        uint256 _dai = vat.dai(address(this));
        uint256 _sin = vat.sin(address(this));
        require(_dai > _sin, "DomainGuest/non-surplus");
        unchecked { wad = (_dai - _sin) / RAY; } // Round against this contract for surplus
        require(wad >= dust, "DomainGuest/dust");

        // Burn the DAI and unload on the other side
        vat.swell(address(this), -_int256(wad * RAY));

        emit Surplus(wad);
    }

    /// @notice Push deficit to the host dss
    /// @dev Should be run by keeper on a regular schedule
    function _deficit() internal returns (uint256 _rid, uint256 wad) {
        require(live == 1, "DomainGuest/not-live");

        _rid = rid++;

        uint256 _dai   = vat.dai(address(this));
        uint256 _sin   = vat.sin(address(this));
        uint256 _dsin  = dsin;
        uint256 _dSinR = _dsin * RAY;
        require(_sin >= _dSinR, "DomainGuest/non-deficit-to-push");
        unchecked { _sin = _sin - _dSinR; }
        require(_sin > _dai, "DomainGuest/non-deficit");
        unchecked { wad = _divup(_sin - _dai, RAY); } // Round up to overcharge for deficit
        require(wad >= dust, "DomainGuest/dust");

        dsin = _dsin + wad;

        emit Deficit(wad);
    }

    /// @notice Merge DAI into surplus
    /// @param _lid Local ordering id
    /// @param wad The amount of DAI that has been sent to this domain [WAD]
    function _rectify(uint256 _lid, uint256 wad) internal ordered(_lid) {
        dsin -= wad;
        vat.swell(address(this), _int256(wad * RAY));

        emit Rectify(wad);
    }

    /// @notice Trigger the end module
    /// @param _lid Local ordering id
    function _cage(uint256 _lid) internal ordered(_lid) {
        require(live == 1, "DomainGuest/not-live");

        live = 0;
        end.cage();

        emit Cage();
    }

    /// @notice Set the cure value for the host
    /// @dev Triggered during shutdown
    function _tell() internal returns (uint256 _rid, uint256 debt) {
        debt = end.debt();
        require(debt > 0 || (vat.debt() == 0 && live == 0), "DomainGuest/end-debt-zero");

        _rid = rid++;

        emit Tell(debt);
    }

    /// @notice Transfer a claim token for the given user
    /// @dev    This will transfer a scaled claim from the end.
    /// @param usr The destination to send the claim tokens to
    /// @param rad The amount of claim tokens to mint
    function _exit(address usr, uint256 rad) internal {
        claimToken.transferFrom(address(end), usr, rad);

        emit Exit(usr, rad);
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
    function _initializeRegisterMint(TeleportGUID calldata teleport) internal {
        // There is no issue with resending these messages as the end TeleportJoin will enforce only-once execution
        require(teleports[getGUIDHash(teleport)], "DomainGuest/teleport-not-registered");

        emit InitializeRegisterMint(teleport);
    }
    function _finalizeRegisterMint(TeleportGUID calldata teleport) internal {
        router.registerMint(teleport);

        emit FinalizeRegisterMint(teleport);
    }

    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external auth {
        daiJoin.join(address(this), amount);
        vat.swell(address(this), -_int256(amount * RAY));
        settlements[sourceDomain][targetDomain] += amount;

        emit Settle(sourceDomain, targetDomain, amount);
    }
    function _initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal returns (uint256 _amount) {
        _amount = settlements[sourceDomain][targetDomain];
        require(_amount > 0, "DomainGuest/settlement-zero");

        settlements[sourceDomain][targetDomain] = 0;

        emit InitializeSettle(sourceDomain, targetDomain, _amount);
    }
    function _finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) internal {
        vat.swell(address(this), _int256(amount * RAY));
        daiJoin.exit(address(this), amount);
        router.settle(sourceDomain, targetDomain, amount);

        emit FinalizeSettle(sourceDomain, targetDomain, amount);
    }
    
}
