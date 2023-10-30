// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IERC20Metadata {
  function decimals() external view returns (uint8);
  function balanceOf(address account) external view returns (uint256);
}

contract UniswapV3Helper {
  address public immutable WETH9;
  ISwapRouter public immutable swapRouter;
  IUniswapV3Factory public immutable  factory;
  uint24[] public poolFees;

  constructor(address _factoryAddr, address _swapRouterAddr, address _WETH9, uint24[] memory _poolFees) {
    factory = IUniswapV3Factory(_factoryAddr);
    swapRouter = ISwapRouter(_swapRouterAddr);
    WETH9 = _WETH9;
    poolFees = _poolFees;
  }

  function mathSqrtPriceX96ToUint(
    uint8 decimalsToken0, 
    uint128 liquidity,
    uint160 sqrtPriceX96 
  ) private pure returns (uint256) {
    uint256 amount0 = FullMath.mulDiv(liquidity, FixedPoint96.Q96, sqrtPriceX96);
    uint256 amount1 = FullMath.mulDiv(liquidity, sqrtPriceX96, FixedPoint96.Q96);
    return (amount1 * 10**decimalsToken0) / amount0;
  }

  function getPrice (
    address tokenA, 
    address tokenB
  ) public view returns (uint24 poolFee, uint256 price, bool isDirectOrder) {
    isDirectOrder = tokenA < tokenB;
    (address token0, address token1) = isDirectOrder ? (tokenA, tokenB) : (tokenB, tokenA);
    uint8 decimalsToken0 = IERC20Metadata(token0).decimals();

    uint128 liquidity = 0;
    uint160 sqrtPriceX96 = 0;

    for (uint256 i = 0; i < poolFees.length; i++) {
      address poolAddress = factory.getPool(token0, token1, poolFees[i]);
      if (poolAddress != address(0)){
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        uint128 _liquidity = pool.liquidity();
        if (_liquidity > liquidity) {
          poolFee = poolFees[i];
          liquidity = _liquidity;
          (sqrtPriceX96,,,,,,) = pool.slot0();
        }        
      }
    }
    price = liquidity > 0 && sqrtPriceX96 > 0 ? mathSqrtPriceX96ToUint(decimalsToken0, liquidity, sqrtPriceX96) : 0;
  }

  function swapExactInputMultihop(address tokensIn, address tokensOut, uint256 amountIn) external returns (uint256 amountOut) {
    (uint24 poolFee,,) = getPrice(tokensIn, tokensOut);
    bytes32[] memory pathParams = new bytes32[](poolFee > 0 ? 3 : 5);
    if (poolFee > 0) {
      pathParams[0] = bytes32(uint256(tokensIn));
      pathParams[1] = bytes32(uint256(poolFee));
      pathParams[2] = bytes32(uint256(tokensOut));
    } else {      
      pathParams[0] = bytes32(uint256(tokensIn));
      (poolFee,,) = getPrice(tokensIn, WETH9);
      pathParams[1] = bytes32(uint256(poolFee));
      pathParams[2] = bytes32(uint256(WETH9));
      (poolFee,,) = getPrice(WETH9, tokensOut);
      pathParams[3] = bytes32(uint256(poolFee));
      pathParams[4] = bytes32(uint256(tokensOut));
    }

    TransferHelper.safeTransferFrom(tokensIn, msg.sender, address(this), amountIn);
    TransferHelper.safeApprove(tokensIn, address(swapRouter), amountIn);

    ISwapRouter.ExactInputParams memory params =
        ISwapRouter.ExactInputParams({
            path: abi.encodePacked(pathParams),
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

    amountOut = swapRouter.exactInput(params);
  }

  function getAmountInMaximum(address tokensIn, address tokensOut, uint256 amountOut) external view returns (uint256 amountInMaximum) {
    amountInMaximum = amountOut;
    (uint24 poolFee, uint256 price, bool isDirectOrder) = getPrice(tokensIn, tokensOut);
    if (poolFee > 0) {
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
    } else {
      (poolFee,price,isDirectOrder) = getPrice(WETH9, tokensOut);
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
      (poolFee,price,isDirectOrder) = getPrice(tokensIn, WETH9);
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
    }
  }
    
  function swapExactOutputMultihop(address refundRecipient, address tokensIn, address tokensOut, uint256 amountOut) external returns (uint256 amountIn) {
    uint256 amountInMaximum = amountOut;
    (uint24 poolFee, uint256 price, bool isDirectOrder) = getPrice(tokensIn, tokensOut);
    bytes32[] memory pathParams = new bytes32[](poolFee > 0 ? 3 : 5);
    if (poolFee > 0) {
      pathParams[0] = bytes32(uint256(tokensIn));
      pathParams[1] = bytes32(uint256(poolFee));
      pathParams[2] = bytes32(uint256(tokensOut));
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
    } else {
      pathParams[4] = bytes32(uint256(tokensOut));
      (poolFee,price,isDirectOrder) = getPrice(WETH9, tokensOut);
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
      pathParams[3] = bytes32(uint256(poolFee));
      pathParams[2] = bytes32(uint256(WETH9));
      (poolFee,price,isDirectOrder) = getPrice(tokensIn, WETH9);
      amountInMaximum = isDirectOrder ? amountInMaximum * 101 / (100 * price) : amountInMaximum * price * 101 / 100;
      pathParams[1] = bytes32(uint256(poolFee));
      pathParams[0] = bytes32(uint256(tokensIn));
    }

    TransferHelper.safeTransferFrom(tokensIn, msg.sender, address(this), amountInMaximum);
    TransferHelper.safeApprove(tokensIn, address(swapRouter), amountInMaximum);

    ISwapRouter.ExactOutputParams memory params =
        ISwapRouter.ExactOutputParams({
            path: abi.encodePacked(pathParams),
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

    amountIn = swapRouter.exactOutput(params);
    if (amountIn < amountInMaximum) {
        TransferHelper.safeApprove(tokensIn, address(swapRouter), 0);
        TransferHelper.safeTransferFrom(tokensIn, refundRecipient, msg.sender, amountInMaximum - amountIn);
    }
  }
}