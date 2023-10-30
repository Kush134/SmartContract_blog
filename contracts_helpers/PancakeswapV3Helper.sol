// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@pancakeswap/v3-core/contracts/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap/v3-core/contracts/interfaces/IPancakeV3Factory.sol";
import "@pancakeswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@pancakeswap/v3-core/contracts/libraries/FullMath.sol";
import "@pancakeswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./Interfaces/IERC20MetadataLite.sol";
import "./Interfaces/IWETH9.sol";
import "./Interfaces/IV3SwapRouter.sol";

contract PancakeswapV3Helper {
    address public WETH9;
    IV3SwapRouter public swapRouter;
    IPancakeV3Factory public factory;
    uint24[] public poolFees;

    struct PriceInfo {
        bool isDirectOrder;
        uint8 decimals;
        uint24 poolFee;
        uint256 price;
    }

    event Received(address indexed sender, uint256 value);

    constructor(address _factoryAddr, address _swapRouterAddr, uint24[] memory _poolFees) {
        factory = IPancakeV3Factory(_factoryAddr);
        swapRouter = IV3SwapRouter(_swapRouterAddr);
        WETH9 = swapRouter.WETH9();
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
    ) public view returns (PriceInfo memory priceInfo) {
        bool isDirectOrder = tokenA < tokenB;
        (address token0, address token1) = isDirectOrder ? (tokenA, tokenB) : (tokenB, tokenA);
        uint8 decimalsToken0 = IERC20MetadataLite(token0).decimals();

        uint128 liquidity = 0;
        uint160 sqrtPriceX96 = 0;
        uint24 poolFee = 0;

        for (uint256 i = 0; i < poolFees.length; i++) {
            address poolAddress = factory.getPool(token0, token1, poolFees[i]);
            if (poolAddress != address(0)){
                IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
                uint128 _liquidity = pool.liquidity();
                if (_liquidity > liquidity) {
                poolFee = poolFees[i];
                liquidity = _liquidity;
                (sqrtPriceX96,,,,,,) = pool.slot0();
                }        
            }
        }
        uint256 price = liquidity > 0 && sqrtPriceX96 > 0 ? mathSqrtPriceX96ToUint(decimalsToken0, liquidity, sqrtPriceX96) : 0;
        return PriceInfo({
            isDirectOrder: isDirectOrder,
            decimals: decimalsToken0,
            poolFee: poolFee,
            price: price
        });
    } 

    function swapExactInput(
        address recipient, 
        address refundRecipient, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn
    ) public returns (uint256 amountOut) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        if (refundRecipient != address(this)){
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        PriceInfo memory priceInfo = getPrice(tokenIn, tokenOut);
        if (priceInfo.poolFee > 0) {
            IV3SwapRouter.ExactInputSingleParams memory params =
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: priceInfo.poolFee,
                    recipient: recipient,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });
            amountOut = swapRouter.exactInputSingle(params);
        } else {
            PriceInfo memory priceInfo1 = getPrice(tokenIn, WETH9);
            PriceInfo memory priceInfo2 = getPrice(WETH9, tokenOut);
            IV3SwapRouter.ExactInputParams memory params =
                IV3SwapRouter.ExactInputParams({
                    path: abi.encodePacked(tokenIn, priceInfo1.poolFee, WETH9, priceInfo2.poolFee, tokenOut),
                    recipient: recipient,
                    amountIn: amountIn,
                    amountOutMinimum: 0
                });
            amountOut = swapRouter.exactInput(params);
        }
        require(amountOut > 0, "amountIn is not enough");
    }

    function swapExactInputFromETH(address tokenOut) external payable returns (uint256 amountOut) {
        IWETH9(WETH9).deposit{value: msg.value}();
        if (tokenOut != WETH9) {
            amountOut = swapExactInput(msg.sender, address(this), WETH9, tokenOut, msg.value);
        } else {
            TransferHelper.safeTransfer(WETH9, msg.sender, msg.value);
            amountOut = msg.value;
        }
    }

    function swapExactInputToETH(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        if (tokenIn != WETH9) {
            amountOut = swapExactInput(address(this), msg.sender, tokenIn, WETH9, amountIn);
        } else {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
            amountOut = amountIn;
        }
        IWETH9(WETH9).withdraw(amountOut);
        TransferHelper.safeTransferETH(msg.sender, amountOut);
    }

    function _getAmountInDerection(uint256 amountOut, uint256 price, bool isDirectOrder, uint8 decimals) private pure returns(uint256){
        return isDirectOrder ? ((10**decimals) * amountOut * 103 / (100 * price)) : (amountOut * price * 103 / (100 * (10**decimals)));
    }
        
    function swapExactOutput(
        address recipient, 
        address refundRecipient, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountInMaximum, 
        uint256 amountOut
    ) public returns (uint256 amountIn) {
        PriceInfo memory priceInfo = getPrice(tokenIn, tokenOut);
        if (priceInfo.poolFee > 0) {
            if (amountInMaximum == 0) {
                amountInMaximum = _getAmountInDerection(amountOut, priceInfo.price, priceInfo.isDirectOrder, priceInfo.decimals);
            }

            TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);
            if (refundRecipient != address(this)) {
                TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInMaximum);
            }

            IV3SwapRouter.ExactOutputSingleParams memory params =
                IV3SwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: priceInfo.poolFee,
                    recipient: recipient,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum,
                    sqrtPriceLimitX96: 0
                });

            amountIn = swapRouter.exactOutputSingle(params);
        } else {
            PriceInfo memory priceInfo2 = getPrice(WETH9, tokenOut);
            PriceInfo memory priceInfo1 = getPrice(tokenIn, WETH9);
            if (amountInMaximum == 0) {
                amountInMaximum = _getAmountInDerection(amountOut, priceInfo2.price, priceInfo2.isDirectOrder, priceInfo2.decimals);
                amountInMaximum = _getAmountInDerection(amountInMaximum, priceInfo1.price, priceInfo1.isDirectOrder, priceInfo1.decimals);
            }
            
            TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);
            if (refundRecipient != address(this)) {
                TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInMaximum);
            }

            IV3SwapRouter.ExactOutputParams memory params =
                IV3SwapRouter.ExactOutputParams({
                    path: abi.encodePacked(tokenIn, priceInfo1.poolFee, WETH9, priceInfo2.poolFee, tokenOut),
                    recipient: recipient,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum
                });

            amountIn = swapRouter.exactOutput(params);
        }

        if (amountIn < amountInMaximum && refundRecipient != address(this)) {
            TransferHelper.safeTransfer(tokenIn, refundRecipient, amountInMaximum - amountIn);
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
        }
    }

    function swapExactOutputFromETH(address refundRecipient, address tokenOut, uint256 amountOut) external payable returns (uint256 amountIn) {
        uint256 amountInMaximum = msg.value;
        if (tokenOut != WETH9) {
            IWETH9(WETH9).deposit{value: amountInMaximum}();
            amountIn = swapExactOutput(msg.sender, address(this), WETH9, tokenOut, amountInMaximum, amountOut);
            if (amountIn < amountInMaximum) {
                IWETH9(WETH9).withdraw(amountInMaximum - amountIn);
                TransferHelper.safeTransferETH(refundRecipient, amountInMaximum - amountIn);
                TransferHelper.safeApprove(WETH9, address(swapRouter), 0);
            }
        } else {
            amountIn = amountOut;
            IWETH9(WETH9).deposit{value: amountIn}();
            TransferHelper.safeTransfer(WETH9, msg.sender, amountIn);
            TransferHelper.safeTransferETH(refundRecipient, amountInMaximum - amountIn);
        }
    }

    function swapExactOutputToETH(address refundRecipient, address tokenIn, uint256 amountInMaximum, uint256 amountOut) external returns (uint256 amountIn) {
        if (tokenIn != WETH9){
            amountIn = swapExactOutput(address(this), refundRecipient, tokenIn, WETH9, amountInMaximum, amountOut);
        } else {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountOut);
            amountIn = amountOut;
        }
        IWETH9(WETH9).withdraw(amountOut);
        TransferHelper.safeTransferETH(msg.sender, amountOut);
    }
    
    // === Support view functions ===
    function convertAmountToETH(address token, uint256 amountIn) external view returns (uint256){
        if (token == WETH9 || token == address(0)) return amountIn;
        
        PriceInfo memory priceInfo = getPrice(token, WETH9);
        return priceInfo.isDirectOrder ? (amountIn * priceInfo.price / (10**priceInfo.decimals)) : (amountIn * (10**priceInfo.decimals) / priceInfo.price);
    }  

    function getAmountInMaximum(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256 amountInMaximum) {
        if (tokenIn == address(0)){
            tokenIn = WETH9;
        }
        if (tokenOut == address(0)){
            tokenOut = WETH9;
        }

        if (tokenIn == tokenOut){
            amountInMaximum = amountOut;
        } else {
            PriceInfo memory priceInfo = getPrice(tokenIn, tokenOut);
            if (priceInfo.poolFee > 0) {
                amountInMaximum = _getAmountInDerection(amountOut, priceInfo.price, priceInfo.isDirectOrder, priceInfo.decimals);
            } else {
                PriceInfo memory priceInfo2 = getPrice(WETH9, tokenOut);
                amountInMaximum = _getAmountInDerection(amountOut, priceInfo2.price, priceInfo2.isDirectOrder, priceInfo2.decimals);
                PriceInfo memory priceInfo1 = getPrice(tokenIn, WETH9);
                amountInMaximum = _getAmountInDerection(amountInMaximum, priceInfo1.price, priceInfo1.isDirectOrder, priceInfo1.decimals);
            }
        }
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}