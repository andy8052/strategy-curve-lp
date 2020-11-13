// SPDX-License-Identifier: AGPLv3

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaultsV2/contracts/BaseStrategy.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/Math.sol";

import "./interfaces/Curve.sol";
import "./interfaces/Iy3Pool.sol";

contract StrategyUSDCy3Pool is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    string public constant override name = "StrategyUSDCy3Pool";
    address public constant crv3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant ycrv3 = 0x9cA85572E6A3EbF24dEDd195623F188735A5179f;
    address public constant curve = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    address public constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 gasFactor = 200;
    uint256 interval = 1000;

    constructor(address _vault) public BaseStrategy(_vault) {
        want.safeApprove(curve, type(uint256).max);
        IERC20(crv3).safeApprove(ycrv3, type(uint256).max);
        IERC20(dai).safeApprove(curve, type(uint256).max);
        IERC20(usdt).safeApprove(curve, type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    /*
     * Provide an accurate estimate for the total amount of assets (principle + return)
     * that this strategy is currently managing, denominated in terms of `want` tokens.
     * This total should be "realizable" e.g. the total value that could *actually* be
     * obtained from this strategy if it were to divest it's entire position based on
     * current on-chain conditions.
     *
     * NOTE: care must be taken in using this function, since it relies on external
     *       systems, which could be manipulated by the attacker to give an inflated
     *       (or reduced) value produced by this function, based on current on-chain
     *       conditions (e.g. this function is possible to influence through flashloan
     *       attacks, oracle manipulations, or other DeFi attack mechanisms).
     *
     * NOTE: It is up to governance to use this function in order to correctly order
     *       this strategy relative to its peers in order to minimize losses for the
     *       Vault based on sudden withdrawals. This value should be higher than the
     *       total debt of the strategy and higher than it's expected value to be "safe".
     */
    function estimatedTotalAssets() public override view returns (uint256) {
        uint256 underlyingSharePrice = ICurveFi(curve).get_virtual_price();
        uint256 pricePerFullShare = Iy3Pool(ycrv3).getPricePerFullShare();
        uint256 balance = Iy3Pool(ycrv3).balanceOf(address(this));
        balance = balance.mul(pricePerFullShare).div(1e18).mul(underlyingSharePrice).div(1e18);
        return balance.add(want.balanceOf(address(this)));
    }

    function gety3poolUSDCBalance() public view returns (uint256) {
        uint256 underlyingSharePrice = ICurveFi(curve).get_virtual_price();
        uint256 pricePerFullShare = Iy3Pool(ycrv3).getPricePerFullShare();
        uint256 balance = Iy3Pool(ycrv3).balanceOf(address(this));
        return balance.mul(pricePerFullShare).div(1e18).mul(underlyingSharePrice).div(1e18);
    }

    /*
     * Perform any strategy unwinding or other calls necessary to capture
     * the "free return" this strategy has generated since the last time it's
     * core position(s) were adusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and should
     * be optimized to minimize losses as much as possible. It is okay to report
     * "no returns", however this will affect the credit limit extended to the
     * strategy and reduce it's overall position if lower than expected returns
     * are sustained for long periods of time.
     */
    function prepareReturn(uint256 _debtOutstanding) internal override returns (uint256 _profit) {
        StrategyParams memory params = vault.strategies(address(this));

        Iy3Pool(ycrv3).earn();

        uint256 _balance = gety3poolUSDCBalance();

        uint256 balanceInWant = want.balanceOf(address(this));
        uint256 total = _balance.add(balanceInWant);
        uint256 debt = vault.strategies(address(this)).totalDebt;

        if(total > debt){
            uint profit = total.sub(debt);
            uint amountToFree = profit.add(_debtOutstanding);
            _profit = liquidatePosition(amountToFree.sub(balanceInWant)).sub(_debtOutstanding);
        } else {
            liquidatePosition(_debtOutstanding.sub(balanceInWant));
            _profit = 0;
        }
    }

    /*
     * Perform any adjustments to the core position(s) of this strategy given
     * what change the Vault made in the "investable capital" available to the
     * strategy. Note that all "free capital" in the strategy after the report
     * was made is available for reinvestment. Also note that this number could
     * be 0, and you should handle that scenario accordingly.
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        setReserve(0);
        uint _amount = want.balanceOf(address(this)).sub(_debtOutstanding);
        if (_amount == 0) return;

        ICurveFi(curve).add_liquidity([0,_amount,0],0);

        Iy3Pool(ycrv3).deposit(IERC20(crv3).balanceOf(address(this)));
    }

    /*
     * Make as much capital as possible "free" for the Vault to take. Some slippage
     * is allowed, since when this method is called the strategist is no longer receiving
     * their performance fee. The goal is for the strategy to divest as quickly as possible
     * while not suffering exorbitant losses. This function is used during emergency exit
     * instead of `prepareReturn()`
     */
    function exitPosition() internal override {
        Iy3Pool(ycrv3).withdraw();

        uint256 _crv3 = IERC20(crv3).balanceOf(address(this));

        ICurveFi(curve).remove_liquidity(_crv3, [uint256(0),0,0]);
    
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        uint256 _usdt = IERC20(usdt).balanceOf(address(this));
        
        if (_dai > 0) {
            ICurveFi(curve).exchange(0, 1, _dai, 0);
        }
        if (_usdt > 0) {
            ICurveFi(curve).exchange(2, 1, _usdt, 0);
        }
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amount`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amount) internal override returns (uint256 _amountFreed) {
        uint _before = want.balanceOf(address(this));

        uint256 underlyingSharePrice = ICurveFi(curve).get_virtual_price();
        uint256 pricePerFullShare = Iy3Pool(ycrv3).getPricePerFullShare();
        uint256 _shares = _amount.mul(1e18).div(underlyingSharePrice).mul(1e18).div(pricePerFullShare);
        Iy3Pool(ycrv3).withdraw(_shares);

        uint256 _crv3 = IERC20(crv3).balanceOf(address(this));

        ICurveFi(curve).remove_liquidity(_crv3, [uint256(0),0,0]);
    
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        uint256 _usdt = IERC20(usdt).balanceOf(address(this));
        
        if (_dai > 0) {
            ICurveFi(curve).exchange(0, 1, _dai, 0);
        }
        if (_usdt > 0) {
            ICurveFi(curve).exchange(2, 1, _usdt, 0);
        }
        
        uint _after = want.balanceOf(address(this));
        
        return _after.sub(_before);
    }

    function setGasFactor(uint256 _gasFactor) public {
        require(msg.sender == strategist || msg.sender == governance());
        gasFactor = _gasFactor;
    }

    function setInterval(uint256 _interval) public {
        require(msg.sender == strategist || msg.sender == governance());
        interval = _interval;
    }

    /*
     * Do anything necessary to prepare this strategy for migration, such
     * as transfering any reserve or LP tokens, CDPs, or other tokens or stores of value.
     */
    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        exitPosition();
        want.transfer(_newStrategy, want.balanceOf(address(this)));
    }

    // NOTE: Override this if you typically manage tokens inside this contract
    //       that you don't want swept away from you randomly.
    //       By default, only contains `want`
    function protectedTokens() internal override view returns (address[] memory) {
        address[] memory protected = new address[](2);
        protected[0] = address(want);
        protected[1] = crv3;
        protected[2] =  ycrv3;
        return protected;
    }

}