// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWithdrawRequestNFT {
    struct WithdrawRequest {
        uint96 amountOfEEth;
        uint96 shareOfEEth;
        bool isValid;
        uint32 feeGwei;
    }

    function claimWithdraw(uint256 _requestId) external;

    function finalizeRequests(uint256 _upperBound) external;

    function getClaimableAmount(uint256 _tokenId) external view returns (uint256);

    function getRequest(uint256 _requestId) external view returns (WithdrawRequest memory);

    function isFinalized(uint256 _requestId) external view returns (bool);
}
