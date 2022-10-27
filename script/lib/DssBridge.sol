// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.14;

import { BridgeOracle } from "../../src/BridgeOracle.sol";
import { ClaimToken } from "../../src/ClaimToken.sol";
import { DomainHost } from "../../src/DomainHost.sol";
import { DomainGuest } from "../../src/DomainGuest.sol";

import { OptimismDomainHost } from "../../src/domains/optimism/OptimismDomainHost.sol";
import { OptimismDomainGuest } from "../../src/domains/optimism/OptimismDomainGuest.sol";
import { ArbitrumDomainHost } from "../../src/domains/arbitrum/ArbitrumDomainHost.sol";
import { ArbitrumDomainGuest } from "../../src/domains/arbitrum/ArbitrumDomainGuest.sol";

struct BridgeInstance {
    BridgeOracle oracle;
    ClaimToken claimToken;
    DomainGuest guest;
    DomainHost host;
}

interface AuthLike {
    function rely(address) external;
    function deny(address) external;
}

// Tools for deploying and setting up a dss-bridge instance
library DssBridge {

    function switchOwner(address base, address newOwner) internal {
        AuthLike(base).rely(newOwner);
        AuthLike(base).deny(address(this));
    }

    function deployOptimismHost(
        address owner,
        bytes32 ilk,
        address daiJoin,
        address escrow,
        address router,
        address l1Messenger,
        address guest
    ) internal returns (BridgeInstance memory bridge) {
        bridge.host = new OptimismDomainHost(
            ilk,
            daiJoin,
            escrow,
            router,
            l1Messenger,
            guest
        );
        bridge.oracle = new BridgeOracle(address(bridge.host));

        switchOwner(address(bridge.host), owner);
        switchOwner(address(bridge.oracle), owner);
    }

    function deployOptimismGuest(
        address owner,
        bytes32 domain,
        address daiJoin,
        address router,
        address l2Messenger,
        address host
    ) internal returns (BridgeInstance memory bridge) {
        bridge.claimToken = new ClaimToken();
        bridge.guest = new OptimismDomainGuest(
            domain,
            daiJoin,
            address(bridge.claimToken),
            router,
            l2Messenger,
            host
        );

        switchOwner(address(bridge.guest), owner);
        switchOwner(address(bridge.claimToken), owner);
    }

    function initHost() internal {
        
    }

    function initGuest() internal {
        
    }

}
