// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.8.0;

import { StarknetLike } from "../../domains/starknet/StarknetDomainHost.sol";

contract  StarknetMock is StarknetLike {
    event LogMessageToL1(
        uint256 indexed fromAddress,
        address indexed toAddress,
        uint256[] payload
    );

    event LogMessageToL2(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[] payload,
        uint256 nonce,
        uint256 fee
    );

    event ConsumedMessageToL1(
        uint256 indexed fromAddress,
        address indexed toAddress,
        uint256[] payload
    );

    event ConsumedMessageToL2(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[] payload,
        uint256 nonce
    );

    event MessageToL2CancellationStarted(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[] payload,
        uint256 nonce
    );

    event MessageToL2Canceled(
        address indexed fromAddress,
        uint256 indexed toAddress,
        uint256 indexed selector,
        uint256[] payload,
        uint256 nonce
    );

    function sendMessageToL2(
        uint256 to,
        uint256 selector,
        uint256[] calldata payload
    ) external payable returns (bytes32, uint256) {
        emit LogMessageToL2(msg.sender, to, selector, payload, 0, msg.value);
        return (0, 0);
    }

    function consumeMessageFromL2(
        uint256 from,
        uint256[] calldata payload
    ) external returns (bytes32) {
        emit ConsumedMessageToL1(from, msg.sender, payload);
        return (0);
    }

    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32) {
        emit MessageToL2CancellationStarted(msg.sender, toAddress, selector, payload, nonce);
        return (0);
    }

    function cancelL1ToL2Message(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external returns (bytes32){
        emit MessageToL2Canceled(msg.sender, toAddress, selector, payload, nonce);
        return (0);
    }
}