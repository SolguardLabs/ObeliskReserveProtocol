// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "../interfaces/IObelisk.sol";

library SafeTransferLib {
    error SafeTransferFailed(address token, address from, address to, uint256 amount);
    error SafeApproveFailed(address token, address spender, uint256 amount);

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed(address(token), address(this), to, amount);
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed(address(token), from, to, amount);
        }
    }

    function safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeCall(IERC20.approve, (spender, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeApproveFailed(address(token), spender, amount);
        }
    }
}
