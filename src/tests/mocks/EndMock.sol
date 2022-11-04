// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.8.0;

import "./VatMock.sol";

interface TokenLike {
    function approve(address, uint256) external returns (bool);
}

contract EndMock {

    VatMock public vat;
    uint256 public live = 1;
    uint256 public debt;

    constructor(address _vat) {
        vat = VatMock(_vat);
    }

    function cage() external {
        live = 0;
        vat.cage();
    }

    function setDebt(uint256 d) external {
        debt = d;
    }

    function approve(address token, address target) external {
        TokenLike(token).approve(target, type(uint256).max);
    }

}
