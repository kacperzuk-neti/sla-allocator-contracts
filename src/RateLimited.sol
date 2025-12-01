// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RateLimited
 * @notice Abstract contract for rate limiting
 */
abstract contract RateLimited is Context, ReentrancyGuard {
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
     * @notice Constructor
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
     * @notice Universal method to check rate limit (returns flag instead of revert)
     * @param rl Reference to the RateLimit struct (storage)
     * @return success True if limit OK (and updates amount), false if exceeded
     * @return resetTime Time when limit resets (only if !success)
     */
    function _checkRateLimit(RateLimit storage rl) internal nonReentrant returns (bool success, uint256 resetTime) {
        uint256 windowTime = rl.isGlobal ? GLOBAL_RATE_LIMIT_TIME : CLIENT_RATE_LIMIT_TIME;
        uint8 maxAmount = rl.isGlobal ? GLOBAL_RATE_LIMIT : CLIENT_RATE_LIMIT;
        if (block.timestamp - rl.lastUpdate > windowTime) {
            rl.amount = 0;
            rl.lastUpdate = block.timestamp;
        }

        if (rl.amount >= maxAmount) {
            return (false, rl.lastUpdate + windowTime);
        }

        return (true, 0);
    }

    /**
     * @notice Modifier to check rate limits
     */
    function checkRateLimit() internal nonReentrant {
        (bool clientSuccess, uint256 clientResetTime) = _checkRateLimit(_clientRateLimits[_msgSender()]);
        if (!clientSuccess) {
            revert ClientRateLimitExceeded(_msgSender(), clientResetTime);
        }
        (bool gSuccess, uint256 gResetTime) = _checkRateLimit(_globalRateLimit);
        if (!gSuccess) {
            revert GlobalRateLimitExceeded(gResetTime);
        }
        _globalRateLimit.amount++;
        _clientRateLimits[_msgSender()].amount++;
    }

    modifier rateLimited() {
        checkRateLimit();
        _;
    }
}
