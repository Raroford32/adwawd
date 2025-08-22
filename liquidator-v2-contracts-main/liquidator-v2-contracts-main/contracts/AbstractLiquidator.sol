// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024
pragma solidity ^0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import {IPartialLiquidator, IntermediateData, LiquidationResult} from "./interfaces/IPartialLiquidator.sol";
import {IRouterV3, RouterResult} from "./interfaces/IRouterV3.sol";
import {IPartialLiquidationBotV3} from "@gearbox-protocol/bots-v3/contracts/interfaces/IPartialLiquidationBotV3.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {
    ICreditManagerV3,
    CollateralDebtData,
    CollateralCalcTask
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {CreditLogic} from "@gearbox-protocol/core-v3/contracts/libraries/CreditLogic.sol";
import {MultiCall, MultiCallOps} from "@gearbox-protocol/core-v2/contracts/libraries/MultiCall.sol";
import {IUpdatablePriceFeed} from "@gearbox-protocol/core-v2/contracts/interfaces/IPriceFeed.sol";

uint256 constant PERCENTAGE_FACTOR = 10000;

abstract contract AbstractLiquidator is Ownable, IPartialLiquidator {
    using SafeERC20 for IERC20;
    using MultiCallOps for MultiCall[];

    event SetRouter(address indexed newRouter);
    event SetPartialLiquidationBot(address indexed partialLiquidationBot);

    address public router;
    address public partialLiquidationBot;

    mapping(address => address) public cmToCA;

    bytes private _liqResultTemp;

    constructor(address _router, address _plb) {
        router = _router;
        partialLiquidationBot = _plb;
    }

    function registerCM(address creditManager) external onlyOwner {
        if (cmToCA[creditManager] != address(0)) revert("Credit Account already exists");

        address creditFacade = ICreditManagerV3(creditManager).creditFacade();
        cmToCA[creditManager] = ICreditFacadeV3(creditFacade).openCreditAccount(address(this), new MultiCall[](0), 0);

        address underlying = ICreditManagerV3(creditManager).underlying();

        IERC20(underlying).forceApprove(partialLiquidationBot, type(uint256).max);
    }

    function withdrawToken(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function _processFlashLoan(address asset, uint256 amount, uint256 premium, IntermediateData memory intData)
        internal
    {
        if (intData.preview) {
            LiquidationResult memory liqResult = _previewPartialLiquidationInt(
                intData.creditManager,
                intData.creditAccount,
                intData.assetOut,
                intData.amountOut,
                intData.priceUpdates,
                intData.connectors,
                intData.slippage
            );

            _liqResultTemp = abi.encode(liqResult);

            _performConversion(intData.creditFacade, intData.conversionAccount, liqResult.calls);
        } else {
            _partialLiquidateInt(
                intData.creditAccount,
                intData.conversionAccount,
                intData.assetOut,
                intData.amountOut,
                intData.priceUpdates
            );

            _performConversion(intData.creditFacade, intData.conversionAccount, intData.conversionCalls);

            require(
                intData.initialUnderlyingBalance + amount + premium < IERC20(asset).balanceOf(address(this)),
                "Liquidation was not profitable"
            );
        }
    }

    function _partialLiquidateInt(
        address creditAccount,
        address conversionAccount,
        address assetOut,
        uint256 amountOut,
        IPartialLiquidationBotV3.PriceUpdate[] memory priceUpdates
    ) internal {
        IPartialLiquidationBotV3(partialLiquidationBot).liquidateExactCollateral(
            creditAccount, assetOut, amountOut, type(uint256).max, conversionAccount, priceUpdates
        );
    }

    function _performConversion(address creditFacade, address conversionAccount, MultiCall[] memory conversionCalls)
        internal
    {
        ICreditFacadeV3(creditFacade).multicall(conversionAccount, conversionCalls);
    }

    function partialLiquidateAndConvert(
        address creditManager,
        address creditAccount,
        address assetOut,
        uint256 amountOut,
        uint256 flashLoanAmount,
        IPartialLiquidationBotV3.PriceUpdate[] calldata priceUpdates,
        MultiCall[] calldata conversionCalls
    ) external onlyOwner {
        IntermediateData memory intData;

        intData.creditManager = creditManager;
        intData.creditAccount = creditAccount;
        intData.assetOut = assetOut;
        intData.amountOut = amountOut;
        intData.priceUpdates = priceUpdates;
        intData.conversionCalls = conversionCalls;
        intData.conversionAccount = cmToCA[creditManager];

        if (intData.conversionAccount == address(0)) revert("Credit Manager not registered");

        intData.creditFacade = ICreditManagerV3(creditManager).creditFacade();

        address underlying = ICreditManagerV3(creditManager).underlying();

        intData.initialUnderlyingBalance = IERC20(underlying).balanceOf(address(this));

        _takeFlashLoan(underlying, flashLoanAmount, abi.encode(intData));
    }

    function previewPartialLiquidation(
        address creditManager,
        address creditAccount,
        address assetOut,
        uint256 amountOut,
        uint256 flashLoanAmount,
        IPartialLiquidationBotV3.PriceUpdate[] calldata priceUpdates,
        address[] calldata connectors,
        uint256 slippage
    ) external returns (LiquidationResult memory res) {
        IntermediateData memory intData;

        intData.preview = true;
        intData.creditManager = creditManager;
        intData.creditAccount = creditAccount;
        intData.assetOut = assetOut;
        intData.amountOut = amountOut;
        intData.priceUpdates = priceUpdates;
        intData.connectors = connectors;
        intData.slippage = slippage;
        intData.conversionAccount = cmToCA[creditManager];

        if (intData.conversionAccount == address(0)) revert("Credit Manager not registered");

        intData.creditFacade = ICreditManagerV3(creditManager).creditFacade();

        address underlying = ICreditManagerV3(creditManager).underlying();

        _takeFlashLoan(underlying, flashLoanAmount, abi.encode(intData));

        return abi.decode(_liqResultTemp, (LiquidationResult));
    }

    function _takeFlashLoan(address underlying, uint256 amount, bytes memory data) internal virtual;

    function _previewPartialLiquidationInt(
        address creditManager,
        address creditAccount,
        address assetOut,
        uint256 amountOut,
        IPartialLiquidationBotV3.PriceUpdate[] memory priceUpdates,
        address[] memory connectors,
        uint256 slippage
    ) internal returns (LiquidationResult memory) {
        address conversionAccount = cmToCA[creditManager];

        uint256 amountIn = IPartialLiquidationBotV3(partialLiquidationBot).liquidateExactCollateral(
            creditAccount, assetOut, amountOut, type(uint256).max, conversionAccount, priceUpdates
        );

        (MultiCall[] memory calls, uint256 amountOutUnderlying) =
            _getConversionResult(creditManager, conversionAccount, assetOut, amountOut, connectors, slippage);

        return LiquidationResult({
            calls: calls,
            amountIn: amountIn,
            amountOut: amountOut,
            profit: int256(amountOutUnderlying) - int256(amountIn)
        });
    }

    function _getConversionResult(
        address creditManager,
        address conversionAccount,
        address assetOut,
        uint256 amountOut,
        address[] memory connectors,
        uint256 slippage
    ) internal returns (MultiCall[] memory, uint256) {
        address underlying = ICreditManagerV3(creditManager).underlying();

        RouterResult memory res =
            IRouterV3(router).findOneTokenPath(assetOut, amountOut, underlying, conversionAccount, connectors, slippage);

        address creditFacade = ICreditManagerV3(creditManager).creditFacade();

        res.calls = res.calls.append(
            MultiCall({
                target: creditFacade,
                callData: abi.encodeCall(
                    ICreditFacadeV3Multicall.withdrawCollateral, (underlying, type(uint256).max, address(this))
                )
            })
        );

        return (res.calls, res.minAmount);
    }

    function getOptimalLiquidation(
        address creditAccount,
        uint256 hfOptimal,
        IPartialLiquidationBotV3.PriceUpdate[] memory priceUpdates
    )
        external
        returns (
            address tokenOut,
            uint256 optimalAmount,
            uint256 repaidAmount,
            uint256 flashLoanAmount,
            bool isOptimalRepayable
        )
    {
        ICreditManagerV3 creditManager = ICreditManagerV3(ICreditAccountV3(creditAccount).creditManager());
        IPriceOracleV3 priceOracle = IPriceOracleV3(creditManager.priceOracle());

        _applyOnDemandPriceUpdates(priceOracle, priceUpdates);

        tokenOut = _getBestTokenOut(creditAccount, creditManager, priceOracle);

        (optimalAmount, repaidAmount, isOptimalRepayable) =
            _getOptimalAmount(creditAccount, tokenOut, hfOptimal, creditManager, priceOracle);
        flashLoanAmount = _getChargedAmount(repaidAmount, creditManager) * 1005 / 1000;
    }

    function _getBestTokenOut(address creditAccount, ICreditManagerV3 creditManager, IPriceOracleV3 priceOracle)
        internal
        view
        returns (address bestToken)
    {
        uint256 enabledTokensMask = creditManager.enabledTokensMaskOf(creditAccount);
        address underlying = creditManager.underlying();
        uint256 bestVal = 0;

        for (uint256 i = 1; i < creditManager.collateralTokensCount(); ++i) {
            if (enabledTokensMask & (1 << i) > 0) {
                (address token,) = creditManager.collateralTokenByMask(1 << i);
                uint256 val = priceOracle.convert(IERC20(token).balanceOf(creditAccount), token, underlying);

                if (val > bestVal) {
                    bestVal = val;
                    bestToken = token;
                }
            }
        }
    }

    function _getOptimalAmount(
        address creditAccount,
        address tokenOut,
        uint256 hfOptimal,
        ICreditManagerV3 creditManager,
        IPriceOracleV3 priceOracle
    ) internal view returns (uint256, uint256, bool) {
        address underlying = creditManager.underlying();

        CollateralDebtData memory cdd =
            creditManager.calcDebtAndCollateral(creditAccount, CollateralCalcTask.DEBT_COLLATERAL_SAFE_PRICES);

        uint256 discount;
        uint256 optimalValueSeized;

        {
            uint256 ltTokenOut = creditManager.liquidationThresholds(tokenOut);

            discount = _getLiquidationDiscount(creditManager);

            optimalValueSeized = (
                CreditLogic.calcTotalDebt(cdd) * hfOptimal
                    - priceOracle.convertFromUSD(cdd.twvUSD, underlying) * PERCENTAGE_FACTOR
            ) / (discount * hfOptimal / PERCENTAGE_FACTOR - ltTokenOut);
        }

        (uint256 optimalAmount, uint256 repaidAmount) =
            _getAmounts(optimalValueSeized, underlying, tokenOut, creditManager, priceOracle);

        return _adjustToDebtLimits(creditManager, optimalAmount, repaidAmount, CreditLogic.calcTotalDebt(cdd));
    }

    function _getLiquidationDiscount(ICreditManagerV3 creditManager) internal view returns (uint256) {
        (, uint256 feeLiquidation, uint256 liquidationDiscount,,) = creditManager.fees();
        uint256 totalFee = (
            (PERCENTAGE_FACTOR - liquidationDiscount)
                * IPartialLiquidationBotV3(partialLiquidationBot).premiumScaleFactor()
                + feeLiquidation * IPartialLiquidationBotV3(partialLiquidationBot).feeScaleFactor()
        ) / PERCENTAGE_FACTOR;
        return PERCENTAGE_FACTOR - totalFee;
    }

    function _getAmounts(
        uint256 optimalValueSeized,
        address underlying,
        address tokenOut,
        ICreditManagerV3 creditManager,
        IPriceOracleV3 priceOracle
    ) internal view returns (uint256, uint256) {
        uint256 discount = _getLiquidationDiscount(creditManager);
        uint256 optimalAmount = _safeConvert(priceOracle, optimalValueSeized, underlying, tokenOut);
        uint256 repaidAmount = priceOracle.convert(optimalAmount, tokenOut, underlying) * discount / PERCENTAGE_FACTOR;

        return (optimalAmount, repaidAmount);
    }

    function _getRepaidAmount(uint256 chargedAmount, ICreditManagerV3 creditManager) internal view returns (uint256) {
        (, uint256 feeLiquidation,,,) = creditManager.fees();
        uint256 partialFeeLiquidation =
            feeLiquidation * IPartialLiquidationBotV3(partialLiquidationBot).feeScaleFactor() / PERCENTAGE_FACTOR;
        return chargedAmount * (PERCENTAGE_FACTOR - partialFeeLiquidation) / PERCENTAGE_FACTOR;
    }

    function _getChargedAmount(uint256 repaidAmount, ICreditManagerV3 creditManager) internal view returns (uint256) {
        (, uint256 feeLiquidation,,,) = creditManager.fees();
        uint256 partialFeeLiquidation =
            feeLiquidation * IPartialLiquidationBotV3(partialLiquidationBot).feeScaleFactor() / PERCENTAGE_FACTOR;
        return repaidAmount * PERCENTAGE_FACTOR / (PERCENTAGE_FACTOR - partialFeeLiquidation);
    }

    function _adjustToDebtLimits(
        ICreditManagerV3 creditManager,
        uint256 optimalAmount,
        uint256 repaidAmount,
        uint256 totalDebt
    ) internal view returns (uint256, uint256, bool) {
        (uint128 minDebt, uint128 maxDebt) = ICreditFacadeV3(creditManager.creditFacade()).debtLimits();

        if (totalDebt > maxDebt && repaidAmount < totalDebt - maxDebt) {
            uint256 requiredRepay = totalDebt - maxDebt;
            optimalAmount = optimalAmount * requiredRepay * 1005 / (repaidAmount * 1000);
            repaidAmount = requiredRepay * 1005 / 1000;
            return (optimalAmount, repaidAmount, false);
        } else if (totalDebt < minDebt) {
            return (0, 0, false);
        } else if (repaidAmount > totalDebt - minDebt) {
            uint256 surplusDebt = totalDebt - minDebt;
            optimalAmount = optimalAmount * surplusDebt * 995 / (repaidAmount * 1000);
            repaidAmount = surplusDebt * 995 / 1000;
            return (optimalAmount, repaidAmount, false);
        }
        return (optimalAmount, repaidAmount, true);
    }

    function _applyOnDemandPriceUpdates(
        IPriceOracleV3 priceOracle,
        IPartialLiquidationBotV3.PriceUpdate[] memory priceUpdates
    ) internal {
        uint256 len = priceUpdates.length;
        for (uint256 i; i < len; ++i) {
            address priceFeed = priceOracle.priceFeedsRaw(priceUpdates[i].token, priceUpdates[i].reserve);
            if (priceFeed == address(0)) revert("Updated price feed does not exist.");
            IUpdatablePriceFeed(priceFeed).updatePrice(priceUpdates[i].data);
        }
    }

    function _safeConvert(IPriceOracleV3 priceOracle, uint256 amount, address underlying, address tokenOut)
        internal
        view
        returns (uint256)
    {
        uint256 underlyingUSD = priceOracle.convertToUSD(amount, underlying);
        uint256 tokenOutPrice = priceOracle.getPriceSafe(tokenOut);
        uint256 tokenOutScale = 10 ** IERC20Metadata(tokenOut).decimals();
        return underlyingUSD * tokenOutScale / tokenOutPrice;
    }

    function setRouter(address newRouter) external onlyOwner {
        if (router == newRouter) return;
        router = newRouter;
        emit SetRouter(newRouter);
    }

    function setPartialLiquidationBot(address newPLB) external onlyOwner {
        if (partialLiquidationBot == newPLB) return;
        partialLiquidationBot = newPLB;
        emit SetPartialLiquidationBot(newPLB);
    }
}
