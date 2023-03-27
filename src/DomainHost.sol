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

interface DomainGuestLike {
    function deposit(address to, uint256 amount) external;
    function lift(uint256 _lid, uint256 wad) external;
    function rectify(uint256 _lid, uint256 wad) external;
    function cage(uint256 _lid) external;
    function exit(address usr, uint256 wad) external;
    function finalizeRegisterMint(TeleportGUID calldata teleport) external;
    function finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external;
}

interface VatLike {
    function live() external view returns (uint256);
    function hope(address usr) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external;
    function suck(address u, address v, uint256 rad) external;
    function urns(bytes32, address) external view returns (uint256, uint256);
    function grab(bytes32, address, address, address, int256, int256) external;
}

interface DaiJoinLike {
    function vat() external view returns (VatLike);
    function dai() external view returns (DaiLike);
    function join(address usr, uint256 wad) external;
    function exit(address usr, uint256 wad) external;
}

interface DaiLike {
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
    function approve(address usr, uint wad) external returns (bool);
}

interface RouterLike {
    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external;
    function registerMint(TeleportGUID calldata teleport) external;
}

/// @title Support for xchain MCD, canonical DAI and Maker Teleport - host instance
/// @dev This is just the business logic which needs concrete message-passing implementation
abstract contract DomainHost {

    // --- Data ---
    mapping (address => uint256) public wards;
    mapping (bytes32 => bool)    public teleports;
    mapping (bytes32 => mapping (bytes32 => uint256)) public settlements;

    address public vow;
    uint256 public lid;         // Local ordering id
    uint256 public rid;         // Remote ordering id
    uint256 public line;        // Remote domain global debt ceiling [RAD]
    uint256 public grain;       // Keep track of the pre-minted DAI in the escrow [WAD]
    uint256 public ddai;        // A running total of how much is ready for realize as surplus [WAD]
    uint256 public dsin;        // A running total of how much is required to re-capitalize the remote domain [WAD]
    bool public debtReported;   // Returns true if debt has been reported by the guest after Global Settlement
    uint256 public debt;        // Total debt reported from the guest after Global Settlement [RAD]
    uint256 public live;

    bytes32     public immutable ilk;
    VatLike     public immutable vat;
    DaiJoinLike public immutable daiJoin;
    DaiLike     public immutable dai;
    address     public immutable escrow;
    RouterLike  public immutable router;

    uint256 constant RAY = 10 ** 27;

    string constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Lift(uint256 rad);
    event Release(uint256 wad);
    event Surplus(uint256 wad);
    event Deficit(uint256 wad);
    event Accrue(uint256 wad);
    event Rectify(uint256 wad);
    event Cage();
    event Tell(uint256 value);
    event Exit(address indexed sender, address indexed usr, uint256 wad, uint256 claim);
    event Exit(address indexed sender, bytes32 indexed usr, uint256 wad, uint256 claim);
    event UndoExit(address indexed sender, address indexed usr, uint256 wad);
    event UndoExit(address indexed sender, bytes32 indexed usr, uint256 wad);
    event Deposit(address indexed sender, address indexed to, uint256 amount);
    event Deposit(address indexed sender, bytes32 indexed to, uint256 amount);
    event UndoDeposit(address indexed sender, address indexed to, uint256 amount);
    event UndoDeposit(address indexed sender, bytes32 indexed to, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event RegisterMint(TeleportGUID teleport);
    event InitializeRegisterMint(TeleportGUID teleport);
    event FinalizeRegisterMint(TeleportGUID teleport);
    event Settle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event InitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event UndoInitializeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);
    event FinalizeSettle(bytes32 indexed sourceDomain, bytes32 indexed targetDomain, uint256 amount);

    modifier auth {
        require(wards[msg.sender] == 1, "DomainHost/not-authorized");
        _;
    }

    modifier ordered(uint256 _lid) {
        require(lid++ == _lid, "DomainHost/out-of-order");
        _;
    }

    constructor(bytes32 _ilk, address _daiJoin, address _escrow, address _router) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        daiJoin = DaiJoinLike(_daiJoin);
        vat = daiJoin.vat();
        dai = daiJoin.dai();
        escrow = _escrow;
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
        if (what == "vow") vow = data;
        else revert("DomainHost/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Canonical DAI Support ---

    /// @notice Deposit local DAI to mint remote canonical DAI
    /// @param to The address to send the DAI to on the remote domain
    /// @param amount The amount of DAI to deposit [WAD]
    function _deposit(address to, uint256 amount) internal {
        dai.transferFrom(msg.sender, escrow, amount);

        emit Deposit(msg.sender, to, amount);
    }

    /// @notice Deposit local DAI to mint remote canonical DAI
    /// @param to The address to send the DAI to on the remote domain
    /// @param amount The amount of DAI to deposit [WAD]
    function _deposit(bytes32 to, uint256 amount) internal {
        dai.transferFrom(msg.sender, escrow, amount);

        emit Deposit(msg.sender, to, amount);
    }

    /// @notice Undo a deposit
    /// @dev    Some chains do not guarantee inclusion of a transaction.
    ///         This function allows the user to undo an exit if it is not relayed
    ///         to the other side.
    ///         It is up to the implementation to ensure this message was not relayed
    ///         otherwise you open yourself up to double spends.
    /// @param sender The msg.sender from the _deposit() call
    /// @param to The address the DAI was supposed to be sent to
    /// @param amount The amount of DAI that was attempted to deposit [WAD]
    function _undoDeposit(address sender, address to, uint256 amount) internal {
        dai.transferFrom(escrow, sender, amount);

        emit UndoDeposit(sender, to, amount);
    }

    /// @notice Undo a deposit
    /// @dev    Some chains do not guarantee inclusion of a transaction.
    ///         This function allows the user to undo an exit if it is not relayed
    ///         to the other side.
    ///         It is up to the implementation to ensure this message was not relayed
    ///         otherwise you open yourself up to double spends.
    /// @param sender The msg.sender from the _deposit() call
    /// @param to The address the DAI was supposed to be sent to
    /// @param amount The amount of DAI that was attempted to deposit [WAD]
    function _undoDeposit(address sender, bytes32 to, uint256 amount) internal {
        dai.transferFrom(escrow, sender, amount);

        emit UndoDeposit(sender, to, amount);
    }

    /// @notice Withdraw local DAI by burning remote canonical DAI
    /// @param to The address to send the DAI to on the local domain
    /// @param amount The amount of DAI to withdraw [WAD]
    function _withdraw(address to, uint256 amount) internal {
        dai.transferFrom(escrow, to, amount);

        emit Withdraw(to, amount);
    }

    // --- MCD Support ---

    /// @notice Set the global debt ceiling for the remote domain
    /// @dev Please note that pre-mint DAI cannot be removed from the remote domain
    /// until the remote domain signals that it is safe to do so
    /// @param wad The new debt ceiling [WAD]
    function _lift(uint256 wad) internal auth returns (uint256 _rid, uint256 rad) {
        require(vat.live() == 1, "DomainHost/vat-not-live");

        rad = wad * RAY;
        uint256 dlineWad;
        int256 dline = _int256(rad) - _int256(line);

        if (dline > 0) {
            // We are issuing new pre-minted DAI
            dlineWad = uint256(dline) / RAY;                    // No precision loss as line is always a multiple of RAY
            vat.slip(ilk, address(this), int256(dlineWad));     // No need for conversion check as amt is under a RAY of full size
            vat.frob(ilk, address(this), address(this), address(this), int256(dlineWad), int256(dlineWad));
            daiJoin.exit(escrow, dlineWad);

            grain += dlineWad;
        }

        line = rad;

        _rid = rid++;

        emit Lift(rad);
    }

    /// @notice Withdraw pre-mint DAI from the remote domain
    /// @param wad The amount of DAI to release [WAD]
    function release(uint256 wad) external auth {
        require(vat.live() == 1, "DomainHost/vat-not-live");

        // Fix any permissionless repays that may have occurred
        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        if (art < ink) {
            address _vow = vow;
            uint256 diff;
            unchecked {
                diff = ink - art;
            }
            vat.suck(_vow, _vow, diff * RAY); // This needs to be done to make sure we can deduct sin[vow] and vice in the next call
            vat.grab(ilk, address(this), address(this), _vow, 0, _int256(diff));
        }

        dai.transferFrom(escrow, address(this), wad);
        daiJoin.join(address(this), wad);
        int256 repay = -_int256(wad);
        vat.frob(ilk, address(this), address(this), address(this), repay, repay);
        vat.slip(ilk, address(this), repay);

        grain -= wad;

        emit Release(wad);
    }

    /// @notice Guest is pushing a surplus
    /// @param _lid Local ordering id
    /// @param wad The amount of DAI to account as ddai [WAD]
    function _surplus(uint256 _lid, uint256 wad) internal ordered(_lid) {
        ddai += wad;

        emit Surplus(wad);
    }

    /// @notice Guest is pushing a deficit
    /// @param _lid Local ordering id
    /// @param wad The amount of DAI to account as dsin [WAD]
    function _deficit(uint256 _lid, uint256 wad) internal ordered(_lid) {
        dsin += wad;

        emit Deficit(wad);
    }

    /// @notice Governance is accruing surplus
    /// @dev This is a potentially dangerous operation as a malicious domain can trigger unintended consequences due to fake surplus
    /// @param _grain It should be the amount of grain necessary to cover debt in the guest domain [WAD]
    /// @param _maxAmount The maximum amount to send to the Surplus Buffer. Used to limit front-running from the 
    ///                   remote domain and allow more flexiblity with how much to send to the Surplus Buffer. [WAD]
    function accrue(uint256 _grain, uint256 _maxAmount) external auth returns (uint256 _wad) {
        require(vat.live() == 1, "DomainHost/vat-not-live");
        _wad = ddai;
        require(_wad > 0, "DomainHost/no-surplus");
        if (_wad > _maxAmount) {
            unchecked { ddai = _wad - _maxAmount; }
            _wad = _maxAmount;
        } else {
            ddai = 0;
        }

        int256 diff = _int256(_grain) - _int256(grain);
        if (diff > 0) {
            vat.slip(ilk, address(this), diff);
            vat.frob(ilk, address(this), address(this), address(this), diff, diff);
            daiJoin.exit(escrow, uint256(diff));
            grain = _grain;
        }

        dai.transferFrom(address(escrow), address(this), _wad);
        daiJoin.join(address(vow), _wad);

        emit Accrue(_wad);
    }

    /// @notice Move bad debt from the remote domain into the local vow
    /// @dev This is a potentially dangerous operation as a malicious domain can drain the entire surplus buffer
    /// Because of this we require an authed party to perform this operation
    /// @param _maxAmount The maximum amount to take from the Surplus Buffer. Used to limit front-running from the 
    ///                   remote domain and allow more flexiblity with how much to take from the Surplus Buffer. [WAD]
    function _rectify(uint256 _maxAmount) internal auth returns (uint256 _rid, uint256 _wad) {
        require(vat.live() == 1, "DomainHost/vat-not-live");
        uint256 _dsin = dsin;
        uint256 _ddai = ddai;
        require(_dsin > _ddai, "DomainHost/no-deficit");

        unchecked { _wad = _dsin - _ddai; }
        if (_wad > _maxAmount) {
            unchecked { dsin = _wad - _maxAmount; }
            _wad = _maxAmount;
        } else {
            dsin = 0;
        }
        ddai = 0;
        vat.suck(vow, address(this), _wad * RAY);
        daiJoin.exit(address(escrow), _wad);

        _rid = rid++;

        emit Rectify(_wad);
    }

    /// @notice Initiate shutdown for this domain
    /// @dev This will trigger the end module on the remote domain
    function _cage() internal returns (uint256 _rid) {
        require(vat.live() == 0 || wards[msg.sender] == 1, "DomainHost/not-authorized");
        require(live == 1, "DomainHost/not-live");

        live = 0;

        _rid = rid++;

        emit Cage();
    }

    /// @notice Process this domain debt
    /// @param _lid Local ordering id
    /// @param _debt The value of debt [RAD]
    function _tell(uint256 _lid, uint256 _debt) internal ordered(_lid) {
        require(live == 0, "DomainHost/live");
        require(!debtReported, "DomainHost/debt-reported");

        uint256 wad = grain + ddai;
        uint256 debtW = _divup(_debt, RAY);
        if (wad > debtW) {
            unchecked {
                wad = wad - debtW;
            }
            dai.transferFrom(address(escrow), address(this), wad);
            daiJoin.join(address(vow), wad);
        }

        debt = _debt;
        debtReported = true;

        emit Tell(_debt);
    }

    /// @notice Allow DAI holders to exit during global settlement
    /// @param usr The address to send the claim token to
    /// @param wad The amount of gems to exit [WAD]
    function _exit(address usr, uint256 wad) internal returns (uint256 claim) {
        require(vat.live() == 0, "DomainHost/vat-live");
        vat.slip(ilk, msg.sender, -_int256(wad));
        claim = wad * (debt / grain); // Round against the user

        emit Exit(msg.sender, usr, wad, claim);
    }

    /// @notice Allow DAI holders to exit during global settlement
    /// @param usr The address to send the claim token to
    /// @param wad The amount of gems to exit [WAD]
    function _exit(bytes32 usr, uint256 wad) internal returns (uint256 claim) {
        require(vat.live() == 0, "DomainHost/vat-live");
        vat.slip(ilk, msg.sender, -_int256(wad));
        claim = wad * (debt / grain); // Round against the user

        emit Exit(msg.sender, usr, wad, claim);
    }

    /// @notice Undo an exit
    /// @dev    Some chains do not guarantee inclusion of a transaction.
    ///         This function allows the user to undo an exit if it is not relayed
    ///         to the other side.
    ///         It is up to the implementation to ensure this message was not relayed
    ///         otherwise you open yourself up to double spends.
    /// @param sender The msg.sender from the _exit() call
    /// @param usr The address the gems were supposed to be sent to
    /// @param wad The amount of gems that was attempted to exit [WAD]
    function _undoExit(address sender, address usr, uint256 wad) internal {
        vat.slip(ilk, sender, _int256(wad));

        emit UndoExit(sender, usr, wad);
    }

    /// @notice Undo an exit
    /// @dev    Some chains do not guarantee inclusion of a transaction.
    ///         This function allows the user to undo an exit if it is not relayed
    ///         to the other side.
    ///         It is up to the implementation to ensure this message was not relayed
    ///         otherwise you open yourself up to double spends.
    /// @param sender The msg.sender from the _exit() call
    /// @param usr The address the gems were supposed to be sent to
    /// @param wad The amount of gems that was attempted to exit [WAD]
    function _undoExit(address sender, bytes32 usr, uint256 wad) internal {
        vat.slip(ilk, sender, _int256(wad));

        emit UndoExit(sender, usr, wad);
    }

    // --- Maker Teleport Support ---

    /// @notice Finalize a teleport registration via the slow path
    function registerMint(TeleportGUID calldata teleport) external auth {
        teleports[getGUIDHash(teleport)] = true;

        emit RegisterMint(teleport);
    }
    function _initializeRegisterMint(TeleportGUID calldata teleport) internal {
        // There is no issue with resending these messages as the end TeleportJoin will enforce only-once execution
        require(teleports[getGUIDHash(teleport)], "DomainHost/teleport-not-registered");

        emit InitializeRegisterMint(teleport);
    }
    function _finalizeRegisterMint(TeleportGUID calldata teleport) internal {
        router.registerMint(teleport);

        emit FinalizeRegisterMint(teleport);
    }

    function settle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) external auth {
        dai.transfer(escrow, amount);
        settlements[sourceDomain][targetDomain] += amount;

        emit Settle(sourceDomain, targetDomain, amount);
    }
    function _initializeSettle(bytes32 sourceDomain, bytes32 targetDomain) internal returns (uint256 _amount) {
        _amount = settlements[sourceDomain][targetDomain];
        require(_amount > 0, "DomainHost/settlement-zero");

        settlements[sourceDomain][targetDomain] = 0;

        emit InitializeSettle(sourceDomain, targetDomain, _amount);
    }
    function _undoInitializeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) internal {
        settlements[sourceDomain][targetDomain] += amount;

        emit UndoInitializeSettle(sourceDomain, targetDomain, amount);
    }
    function _finalizeSettle(bytes32 sourceDomain, bytes32 targetDomain, uint256 amount) internal {
        dai.transferFrom(escrow, address(this), amount);
        router.settle(sourceDomain, targetDomain, amount);

        emit FinalizeSettle(sourceDomain, targetDomain, amount);
    }

}
