// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.15;

import "dss-interfaces/Interfaces.sol";
import { DssInstance } from "dss-test/MCD.sol";

import { TeleportLinearFee } from 'dss-teleport/TeleportLinearFee.sol';
import { TeleportFees } from 'dss-teleport/TeleportFees.sol';
import { TeleportJoin } from 'dss-teleport/TeleportJoin.sol';
import { TeleportOracleAuth } from 'dss-teleport/TeleportOracleAuth.sol';
import { TeleportRouter } from 'dss-teleport/TeleportRouter.sol';

struct TeleportInstance {
    TeleportJoin join;
    TeleportRouter router;
    TeleportOracleAuth oracleAuth;
}

struct DssTeleportConfig {
    uint256 debtCeiling;    // RAD
    uint256 oracleThreshold;
    address[] oracleSigners;
}

struct DssTeleportDomainConfig {
    bytes32 domain;
    address fees;
    address gateway;
    uint256 debtCeiling;    // WAD
}

// Tools for deploying and setting up a dss-teleport instance
library DssTeleport {

    function switchOwner(address base, address deployer, address newOwner) internal {
        require(WardsAbstract(base).wards(deployer) == 1, "deployer-not-authed");
        WardsAbstract(base).rely(newOwner);
        WardsAbstract(base).deny(deployer);
    }

    function deploy(
        address deployer,
        address owner,
        bytes32 ilk,
        bytes32 domain,
        bytes32 parentDomain,
        address daiJoin
    ) internal returns (TeleportInstance memory teleport) {
        teleport.join = new TeleportJoin(
            DaiJoinAbstract(daiJoin).vat(),
            daiJoin,
            ilk,
            domain
        );
        teleport.router = new TeleportRouter(
            DaiJoinAbstract(daiJoin).dai(),
            domain,
            parentDomain
        );
        teleport.oracleAuth = new TeleportOracleAuth(address(teleport.join));

        switchOwner(address(teleport.join), deployer, owner);
        switchOwner(address(teleport.router), deployer, owner);
        switchOwner(address(teleport.oracleAuth), deployer, owner);
    }

    function deployLinearFee(
        uint256 fee,
        uint256 ttl
    ) internal returns (TeleportFees) {
        return new TeleportLinearFee(fee, ttl);
    }

    function init(
        DssInstance memory dss,
        TeleportInstance memory teleport,
        DssTeleportConfig memory cfg
    ) internal {
        bytes32 ilk = teleport.join.ilk();
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.vat.file(ilk, "line", cfg.debtCeiling);
        dss.vat.file("Line", dss.vat.Line() + cfg.debtCeiling);
        dss.vat.file(ilk, "spot", 10 ** 27);
        dss.cure.lift(address(teleport.join));
        dss.vat.rely(address(teleport.join));
        teleport.join.rely(address(teleport.oracleAuth));
        teleport.join.rely(address(teleport.router));
        //teleport.join.rely(esm);
        teleport.join.file("vow", address(dss.vow));
        //teleport.oracleAuth.rely(esm);
        teleport.oracleAuth.file("threshold", cfg.oracleThreshold);
        teleport.oracleAuth.addSigners(cfg.oracleSigners);
        //teleport.router.rely(esm);
        teleport.router.file("gateway", teleport.join.domain(), address(teleport.join));
    }

    function initDomain(
        TeleportInstance memory teleport,
        DssTeleportDomainConfig memory cfg
    ) internal {
        teleport.join.file("fees", cfg.domain, cfg.fees);
        teleport.join.file("line", cfg.domain, cfg.debtCeiling);
        teleport.router.file("gateway", cfg.domain, cfg.gateway);
    }

}
