// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/IUnlockCallback.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {CurrencyLib} from "../libraries/CurrencyLib.sol";
import {MIN_SQRT_PRICE, MAX_SQRT_PRICE} from "../Constants.sol";

/// @title Swap
/// @notice Minimal exact-input single-hop swap router for Uniswap V4.
/// @dev    V4 uses a singleton PoolManager with "flash accounting": the caller
///         must first unlock the manager, and all pool interactions happen
///         inside the unlockCallback. Net token balances (deltas) accumulated
///         during the callback must be settled to zero before it returns,
///         otherwise the unlock reverts.
contract Swap is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;
    using CurrencyLib for address;

    IPoolManager public immutable poolManager;

    /// @param poolKey      Identifies the pool (currencies, fee, tick spacing, hooks).
    /// @param zeroForOne   Direction of the swap: true swaps currency0 -> currency1.
    /// @param amountIn     Exact amount of input currency the user wants to spend.
    /// @param amountOutMin Minimum acceptable output; reverts on slippage below this.
    struct SwapExactInputSingleHop {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMin;
    }

    /// @dev unlockCallback is only ever a legitimate call when re-entered by
    ///      the PoolManager during our own unlock(). Anyone else calling it
    ///      directly would be trying to forge a swap context.
    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @dev Required to receive ETH refunded by the PoolManager when the input
    ///      currency is native ETH (address(0)).
    receive() external payable {}

    /// @notice Callback invoked by the PoolManager after we call unlock().
    ///         All swap logic lives here because V4 only allows pool mutations
    ///         while the manager is unlocked.
    /// @param data ABI-encoded (originalCaller, swap params). We pass the
    ///             original user through `data` because inside this function
    ///             msg.sender is the PoolManager, not the user.
    function unlockCallback(bytes calldata data)
        external
        onlyPoolManager
        returns (bytes memory)
    {
        (address msgSender, SwapExactInputSingleHop memory params) =
            abi.decode(data, (address, SwapExactInputSingleHop));

        // Execute the swap against the pool. The returned int256 packs two
        // signed int128 deltas (amount0, amount1) representing how the pool's
        // accounting changed from this contract's perspective.
        int256 d = poolManager.swap({
            key: params.poolKey,
            params: SwapParams({
                zeroForOne: params.zeroForOne,
                // Sign convention for amountSpecified:
                //   negative = exact input  (we know how much we're spending)
                //   positive = exact output (we know how much we want to receive)
                // We're doing exact-input, so we negate amountIn.
                amountSpecified: -(params.amountIn.toInt256()),
                // Price limit guard. Price is expressed as currency1/currency0:
                //   zeroForOne = true  -> we sell token0 for token1, pushing price down,
                //                         so the limit is the *minimum* price.
                //   zeroForOne = false -> we sell token1 for token0, pushing price up,
                //                         so the limit is the *maximum* price.
                // Using MIN+1 / MAX-1 effectively disables the limit (swap as far
                // as needed to fill amountIn). A real router would expose this.
                sqrtPriceLimitX96: params.zeroForOne
                    ? MIN_SQRT_PRICE + 1
                    : MAX_SQRT_PRICE - 1
            }),
            hookData: ""
        });

        // Unpack the delta. Per-currency convention from this contract's POV:
        //   negative delta = we owe the pool that much (input side)
        //   positive delta = the pool owes us that much (output side)
        BalanceDelta delta = BalanceDelta.wrap(d);
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Map (amount0, amount1) onto (in, out) based on swap direction, and
        // flip the sign of the input side so we work with positive magnitudes.
        (
            address currencyIn,
            address currencyOut,
            uint256 amountIn,
            uint256 amountOut
        ) = params.zeroForOne
            ? (
                params.poolKey.currency0,
                params.poolKey.currency1,
                (-amount0).toUint256(),
                amount1.toUint256()
            )
            : (
                params.poolKey.currency1,
                params.poolKey.currency0,
                (-amount1).toUint256(),
                amount0.toUint256()
            );

        // Slippage check before we actually pull the output funds.
        require(amountOut >= params.amountOutMin, "amount out < min");

        // Settle the positive (output) delta: pull the owed tokens out of the
        // PoolManager directly to the user. This zeros out the output side.
        poolManager.take({
            currency: currencyOut,
            to: msgSender,
            amount: amountOut
        });

        // Settle the negative (input) delta. V4 uses a "sync then pay then settle"
        // pattern for ERC20s: sync() snapshots the manager's current balance of
        // the input currency, we transfer the tokens in, and settle() credits
        // the difference against our debt. For native ETH we skip the transfer
        // and just forward value with settle().
        poolManager.sync(currencyIn);

        if (currencyIn == address(0)) {
            poolManager.settle{value: amountIn}();
        } else {
            IERC20(currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }

        // Both deltas are now zero, so the manager will allow unlock to return.
        return "";
    }

    /// @notice Swap an exact amount of input currency for as much output as
    ///         the pool will give, subject to amountOutMin.
    /// @dev    Pulls the input from the user, kicks off the unlock/callback
    ///         dance, and refunds any unused input (e.g. if the pool consumed
    ///         less than expected, or if extra ETH was sent).
    function swap(SwapExactInputSingleHop calldata params) external payable {
        address currencyIn = params.zeroForOne
            ? params.poolKey.currency0
            : params.poolKey.currency1;

        // Move the input funds into this contract first; the callback will
        // forward them to the PoolManager during settle().
        currencyIn.transferIn(msg.sender, uint256(params.amountIn));

        // unlock() re-enters this contract via unlockCallback, where the
        // actual swap is performed. Reverts bubble up from there.
        poolManager.unlock(abi.encode(msg.sender, params));

        // Refund any leftover input currency. This covers two cases:
        //   1. ETH overpayment (msg.value > amountIn).
        //   2. Defensive cleanup if any input dust remains for any reason.
        uint256 bal = currencyIn.balanceOf(address(this));
        if (bal > 0) {
            currencyIn.transferOut(msg.sender, bal);
        }
    }
}