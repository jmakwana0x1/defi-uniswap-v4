# Universal Router

- [`UniversalRouter`](https://docs.uniswap.org/contracts/universal-router/overview)
- How it works
  - [`execute`](https://github.com/Uniswap/universal-router/blob/3663f6db6e2fe121753cd2d899699c2dc75dca86/contracts/UniversalRouter.sol#L44-L62)
  - [`dispatch`](https://github.com/Uniswap/universal-router/blob/3663f6db6e2fe121753cd2d899699c2dc75dca86/contracts/base/Dispatcher.sol#L47-L286)
  - [`Commands`](https://github.com/Uniswap/universal-router/blob/main/contracts/libraries/Commands.sol)
  - [Commands and inputs](https://docs.uniswap.org/contracts/universal-router/technical-reference)
  - [`V4SwapRouter`](https://github.com/Uniswap/universal-router/blob/main/contracts/modules/uniswap/v4/V4SwapRouter.sol)
  - [`IV4Router`](https://github.com/Uniswap/v4-periphery/blob/main/src/interfaces/IV4Router.sol)
- UniversalRouter and Permit2
  - [`V4SwapRouter`](https://github.com/Uniswap/universal-router/blob/main/contracts/modules/uniswap/v4/V4SwapRouter.sol)
  - [`DeltaResolver`](https://github.com/Uniswap/v4-periphery/blob/main/src/base/DeltaResolver.sol)
  - [`payOrPermit2Transfer`](https://github.com/Uniswap/universal-router/blob/3663f6db6e2fe121753cd2d899699c2dc75dca86/contracts/modules/Permit2Payments.sol#L42-L45)
- [Exercise - execute UniversalRouter commands](./foundry/exercises/universal_router.md)
- [V3 to V4 Multi hop swap](./notes/uni_router_v3_v4_swap.png)
- [Exercise - Multi hop swap on V3 and then V4](./foundry/exercises/swap_v3_v4.md)
- [Exercise - Quoter](./foundry/exercises/quoter.md)
- [Application - liquidation](./foundry/exercises/liquidation.md)
