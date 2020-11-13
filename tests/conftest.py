import json
import pytest

@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass

@pytest.fixture
def vault(Vault, gov, rewards, guardian, token, whale):
    vault = Vault.deploy(
        "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        gov,
        rewards,
        "yvUSDC-Vault",
        "yvUSDC",
        {"from": guardian},
    )
    vault.setManagementFee(0, {"from": gov})
    token.approve(vault, token.balanceOf(whale), {"from": whale})
    deposit = 1000000000000
    vault.deposit(deposit, {"from": whale})
    assert token.balanceOf(vault) == vault.balanceOf(whale) == deposit
    assert vault.totalDebt() == 0  # No connected strategies yet
    return vault


@pytest.fixture
def strategy(StrategyUSDCy3Pool, vault, strategist, token, keeper, gov):
    strategy = StrategyUSDCy3Pool.deploy(
        vault, {"from": strategist}
    )

    strategy.setKeeper(keeper, {"from": strategist})
    vault.addStrategy(
        strategy,
        token.totalSupply() / 2,  # Debt limit of 50% total supply
        token.totalSupply() // 1000,  # Rate limt of 0.1% of token supply per block
        50,  # 0.5% performance fee for Strategist
        {"from": gov},
    )
    return strategy


@pytest.fixture
def succ_strategy(StrategyUSDCy3Pool, vault, strategist, keeper):
    strategy = StrategyUSDCy3Pool.deploy(
        vault, {"from": strategist}
    )
    strategy.setKeeper(keeper, {"from": strategist})
    return strategy

@pytest.fixture
def gov(accounts):
    return accounts[1]

@pytest.fixture
def rewards(gov):
    return gov

@pytest.fixture
def guardian(accounts):
    return accounts[2]

@pytest.fixture
def strategist(accounts):
    return accounts[3]

@pytest.fixture
def keeper(accounts):
    return accounts[4]

@pytest.fixture
def whale(accounts):
    # MKR USDC join
    return accounts.at("0xA191e578a6736167326d05c119CE0c90849E84B7", force=True)

@pytest.fixture
def token(interface):
    return interface.ERC20("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")