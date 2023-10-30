// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

interface IUniswapV3Helper {
    struct PriceInfo {
        bool isDirectOrder;
        uint8 decimals;
        uint24 poolFee;
        uint256 price;
    }

    function WETH9() external view returns (address);

    function getPrice (address tokenA, address tokenB) external view returns (PriceInfo memory priceInfo);

    function swapExactInput(
        address recipient, 
        address refundRecipient, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn
    ) external returns (uint256 amountOut);

    function swapExactInputFromETH(address tokenOut) external payable returns (uint256 amountOut);

    function swapExactInputToETH(address tokenIn, uint256 amountIn) external returns (uint256 amountOut);

    function swapExactOutput(
        address recipient, 
        address refundRecipient, 
        address tokenIn, 
        address tokenOut, 
        uint256 amountInMaximum, 
        uint256 amountOut
    ) external returns (uint256 amountIn);

    function swapExactOutputFromETH(address refundRecipient, address tokenOut, uint256 amountOut) external payable returns (uint256 amountIn);

    function swapExactOutputToETH(address refundRecipient, address tokenIn, uint256 amountInMaximum, uint256 amountOut) external returns (uint256 amountIn);

    // === Support view functions ===
    function convertAmountToETH(address token, uint256 amountIn) external view returns (uint256);
    function getAmountInMaximum(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256 amountInMaximum);
}