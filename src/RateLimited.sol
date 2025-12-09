// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RateLimited
 * @notice Abstract contract for rate limiting
 */
abstract contract RateLimited {
    /**
     * @notice Global rate limit
     */
    uint8 public immutable GLOBAL_RATE_LIMIT = 5;
    /**
     * @notice Client rate limit
     */
    uint8 public immutable CLIENT_RATE_LIMIT = 1;
    /**
     * @notice Global rate limit time
     */
    uint256 public immutable GLOBAL_RATE_LIMIT_TIME = 1 days;
    /**
     * @notice Client rate limit time
     */
    uint256 public immutable CLIENT_RATE_LIMIT_TIME = 1 weeks;

    /**
     * @notice Global rate limit
     */
    RateLimit private _globalRateLimit;

    /**
     * @notice Client rate limits
     */
    mapping(address client => RateLimit _clientRateLimit) private _clientRateLimits;

    /**
     * @notice Rate limit struct
     */
    struct RateLimit {
        bool isGlobal;
        uint8 amount;
        uint256 lastUpdate;
    }

    /**
     * @notice Initializes the global rate limit
     */
    constructor() {
        _globalRateLimit = RateLimit({isGlobal: true, amount: 0, lastUpdate: block.timestamp});
    }

    /**
     * @notice Error emitted when the client rate limit is exceeded
     */
    error ClientRateLimitExceeded(address client, uint256 timeToReset);

    /**
     * @notice Error emitted when the global rate limit is exceeded
     */
    error GlobalRateLimitExceeded(uint256 timeToReset);

    /**
     * @notice Universal method to check rate limit
     * @param rl Reference to the RateLimit struct (storage)
     * @return success Flag indicating if the limit is exceeded
     * @return resetTime Time when limit resets
     */
    function _checkRateLimit(RateLimit storage rl) internal returns (bool success, uint256 resetTime) {
        uint256 windowTime = rl.isGlobal ? GLOBAL_RATE_LIMIT_TIME : CLIENT_RATE_LIMIT_TIME;
        uint8 maxAmount = rl.isGlobal ? GLOBAL_RATE_LIMIT : CLIENT_RATE_LIMIT;
        if (block.timestamp - rl.lastUpdate > windowTime) {
            rl.amount = 0;
            rl.lastUpdate = block.timestamp;
        }

        if (rl.amount == maxAmount) {
            return (false, rl.lastUpdate + windowTime);
        }

        rl.amount++;
        return (true, 0);
    }

    modifier globallyRateLimited() {
        (bool success, uint256 resetTime) = _checkRateLimit(_globalRateLimit);
        if (!success) {
            revert GlobalRateLimitExceeded(resetTime);
        }
        _;
    }

    modifier clientRateLimited() {
        (bool success, uint256 resetTime) = _checkRateLimit(_clientRateLimits[msg.sender]);
        if (!success) {
            revert ClientRateLimitExceeded(msg.sender, resetTime);
        }
        _;
    }
}
