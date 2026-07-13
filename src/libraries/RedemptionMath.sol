// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library RedemptionMath {
    uint256 internal constant BPS = 10_000;

    struct RedemptionTerms {
        uint256 stableAmount;
        uint256 feeBps;
        uint256 price;
        uint8 decimals;
        uint48 createdAt;
        uint48 executionDelay;
        uint48 deadline;
    }

    struct RedemptionPreview {
        uint256 grossValue;
        uint256 feeValue;
        uint256 netValue;
        uint256 assetOut;
        uint48 executableAt;
        bool executable;
        bool expired;
    }

    struct BatchProgress {
        uint256 requested;
        uint256 processed;
        uint256 skipped;
        uint256 valueProcessed;
        bool reachedLimit;
    }

    error RedemptionInvalidBps(uint256 bps);
    error RedemptionInvalidPrice();
    error RedemptionInvalidDecimals(uint8 decimals);
    error RedemptionInvalidDeadline();
    error RedemptionInvalidAmount();

    function preview(RedemptionTerms memory terms, uint48 nowTs)
        internal
        pure
        returns (RedemptionPreview memory result)
    {
        if (terms.stableAmount == 0) revert RedemptionInvalidAmount();
        if (terms.feeBps > BPS) revert RedemptionInvalidBps(terms.feeBps);
        if (terms.price == 0) revert RedemptionInvalidPrice();
        if (terms.decimals > 36) revert RedemptionInvalidDecimals(terms.decimals);
        uint48 executableTimestamp = terms.createdAt + terms.executionDelay;
        if (terms.deadline <= executableTimestamp) revert RedemptionInvalidDeadline();

        uint256 feeValue = terms.stableAmount * terms.feeBps / BPS;
        uint256 net = terms.stableAmount - feeValue;
        result = RedemptionPreview({
            grossValue: terms.stableAmount,
            feeValue: feeValue,
            netValue: net,
            assetOut: valueToAsset(net, terms.price, terms.decimals),
            executableAt: executableTimestamp,
            executable: nowTs >= executableTimestamp && nowTs <= terms.deadline,
            expired: nowTs > terms.deadline
        });
    }

    function valueToAsset(uint256 value, uint256 price, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        if (price == 0) revert RedemptionInvalidPrice();
        if (decimals > 36) revert RedemptionInvalidDecimals(decimals);
        return value * (10 ** uint256(decimals)) / price;
    }

    function assetToValue(uint256 amount, uint256 price, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        if (price == 0) revert RedemptionInvalidPrice();
        if (decimals > 36) revert RedemptionInvalidDecimals(decimals);
        return amount * price / (10 ** uint256(decimals));
    }

    function fee(uint256 stableAmount, uint256 feeBps) internal pure returns (uint256) {
        if (feeBps > BPS) revert RedemptionInvalidBps(feeBps);
        return stableAmount * feeBps / BPS;
    }

    function netOfFee(uint256 stableAmount, uint256 feeBps) internal pure returns (uint256) {
        return stableAmount - fee(stableAmount, feeBps);
    }

    function executableAt(uint48 createdAt, uint48 delay) internal pure returns (uint48) {
        return createdAt + delay;
    }

    function validateDeadline(uint48 createdAt, uint48 delay, uint48 deadline) internal pure {
        if (deadline <= createdAt + delay) revert RedemptionInvalidDeadline();
    }

    function batchProgress(
        uint256 requested,
        uint256 processed,
        uint256 valueProcessed,
        uint256 maxItems
    ) internal pure returns (BatchProgress memory progress) {
        progress.requested = requested;
        progress.processed = processed;
        progress.valueProcessed = valueProcessed;
        progress.skipped = requested > processed ? requested - processed : 0;
        progress.reachedLimit = maxItems != 0 && processed >= maxItems && processed < requested;
    }

    function maxProcessable(uint256 pendingTickets, uint256 requestedLimit)
        internal
        pure
        returns (uint256)
    {
        if (requestedLimit == 0 || requestedLimit > pendingTickets) return pendingTickets;
        return requestedLimit;
    }

    function pressureBps(uint256 pendingStable, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        if (totalSupply == 0) return pendingStable == 0 ? 0 : type(uint256).max;
        return pendingStable * BPS / totalSupply;
    }

    function wouldExpire(uint48 deadline, uint48 nowTs, uint48 grace) internal pure returns (bool) {
        return nowTs + grace > deadline;
    }

    function isWithinWindow(uint48 nowTs, uint48 executableAt_, uint48 deadline)
        internal
        pure
        returns (bool)
    {
        return nowTs >= executableAt_ && nowTs <= deadline;
    }
}
