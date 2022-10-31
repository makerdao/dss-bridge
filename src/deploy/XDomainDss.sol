// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";

import { Cure } from "xdomain-dss/Cure.sol";
import { Dai } from "xdomain-dss/Dai.sol";
import { DaiJoin } from "xdomain-dss/DaiJoin.sol";
import { End } from "xdomain-dss/End.sol";
import { Pot } from "xdomain-dss/Pot.sol";
import { Jug } from "xdomain-dss/Jug.sol";
import { Spotter } from "xdomain-dss/Spotter.sol";
import { Vat } from "xdomain-dss/Vat.sol";

// Tools for deploying and setting up an xdomain-dss instance
library XDomainDss {

    function switchOwner(address base, address deployer, address newOwner) internal {
        WardsAbstract(base).rely(newOwner);
        WardsAbstract(base).deny(deployer);
    }

    function deploy(address deployer, address owner, address dai) internal returns (DssInstance memory dss) {
        dss.vat = VatAbstract(address(new Vat()));
        dss.dai = DaiAbstract(address(Dai(dai)));
        dss.daiJoin = DaiJoinAbstract(address(new DaiJoin(address(dss.vat), address(dss.dai))));
        //dss.dog = DaiAbstract(address(new Dog()));  // Needs merge in xdomain-dss
        dss.spotter = SpotAbstract(address(new Spotter(address(dss.vat))));
        dss.pot = PotAbstract(address(new Pot(address(dss.vat))));
        dss.jug = JugAbstract(address(new Jug(address(dss.vat))));
        dss.cure = CureAbstract(address(new Cure()));
        dss.end = EndAbstract(address(new End()));

        switchOwner(address(dss.vat), deployer, owner);
        switchOwner(address(dss.spotter), deployer, owner);
        switchOwner(address(dss.pot), deployer, owner);
        switchOwner(address(dss.jug), deployer, owner);
        switchOwner(address(dss.cure), deployer, owner);
        switchOwner(address(dss.end), deployer, owner);
    }

    function deploy(address deployer, address owner) internal returns (DssInstance memory dss) {
        dss = deploy(deployer, owner, address(new Dai()));

        switchOwner(address(dss.dai), deployer, owner);
    }

    function init(
        DssInstance memory dss,
        uint256 endWait
    ) internal {
        dss.vat.rely(address(dss.jug));
        //dss.vat.rely(address(dss.dog));
        dss.vat.rely(address(dss.pot));
        dss.vat.rely(address(dss.jug));
        dss.vat.rely(address(dss.spotter));
        dss.vat.rely(address(dss.end));

        dss.dai.rely(address(dss.daiJoin));

        //dss.dog.file("vow", address(dss.vow));

        dss.pot.rely(address(dss.end));

        dss.spotter.rely(address(dss.end));

        dss.end.file("vat", address(dss.vat));
        dss.end.file("pot", address(dss.pot));
        dss.end.file("spot", address(dss.spotter));
        dss.end.file("cure", address(dss.cure));
        //dss.end.file("vow", address(dss.vow));

        dss.end.file("wait", endWait);

        dss.cure.rely(address(dss.end));

        // daiJoin needs a vat.dai balance to match the existing dai supply
        uint256 totalSupply = dss.dai.totalSupply();
        Vat(address(dss.vat)).swell(address(dss.daiJoin), int256(totalSupply) * 10 ** 27);
    }

}
