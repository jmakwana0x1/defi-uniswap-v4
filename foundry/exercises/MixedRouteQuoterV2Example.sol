//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";

address constant V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
address constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
address constant V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract MixedRouteQuoterV2Example is Test {
    MixedRouteQuoterV2 quoter;

    function setUp() public {
        quoter = new MixedRouteQuoterV2(IPoolManager(V4_POOL_MANAGER), V3_FACTORY, V2_FACTORY);
    }

    function test_quote_v4() public {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(USDC),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        uint256 amountIn = 1e18;
        (uint256 amountOut, uint256 gasEstimate) = quoter.quoteExactInputSingleV4(
            IMixedRouteQuoterV2.QuoteExactInputSingleV4Params({
                poolKey: poolKey,
                zeroForOne: true,
                exactAmount: amountIn,
                hookData: ""
            })
        );

        console.log("ETH in: %e", amountIn);
        console.log("USDC out: %e", amountOut);
    }
}
