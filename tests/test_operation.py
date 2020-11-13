blocks_per_year = 6525 * 365
seconds_per_block = (86400 * 365) / blocks_per_year
sample = 200


def sleep(chain):
    chain.mine(sample)
    chain.sleep(int(sample * seconds_per_block))


def test_vault_deposit(vault, token, whale):
    before = vault.balanceOf(whale)
    deposit = token.balanceOf(whale)
    vault.deposit(deposit, {"from": whale})
    assert vault.balanceOf(whale) == before + deposit
    assert token.balanceOf(vault) == before + deposit
    assert vault.totalDebt() == 0
    assert vault.pricePerShare() == 10 ** token.decimals()  # 1:1 price


def test_vault_withdraw(vault, token, whale):
    balance = token.balanceOf(whale) + vault.balanceOf(whale)
    vault.withdraw(vault.balanceOf(whale), {"from": whale})
    assert vault.totalSupply() == token.balanceOf(vault) == 0
    assert vault.totalDebt() == 0
    assert token.balanceOf(whale) == balance


def test_strategy_harvest(strategy, vault, token, whale, chain):
    print('vault:', vault.name())
    user_before = token.balanceOf(whale) + vault.balanceOf(whale)
    print(user_before)
    # token.approve(vault, token.balanceOf(whale), {"from": whale})
    # vault.deposit(token.balanceOf(whale), {"from": whale})
    sleep(chain)
    print("share price before:", vault.pricePerShare().to("ether"))
    assert vault.creditAvailable(strategy) > 0
    # give the strategy some debt
    strategy.harvest()
    before = strategy.estimatedTotalAssets()
    print("Est total assets:", before)
    # run strategy for some time
    sleep(chain)
    print("Want balance|strategy:", token.balanceOf(strategy))
    print("Want balance|vault:", token.balanceOf(vault))
    print("Assets:", strategy.estimatedTotalAssets().to("ether"))
    print("share price before:", vault.pricePerShare().to("ether"))
    print("vault info:", vault.strategies(strategy))
    strategy.harvest()
    sleep(chain)
    strategy.harvest()
    print("Want balance|strategy:", token.balanceOf(strategy))
    print("Want balance|vault:", token.balanceOf(vault))
    print("Assets:", strategy.estimatedTotalAssets().to("ether"))
    print("share price before:", vault.pricePerShare().to("ether"))
    print("vault info:", vault.strategies(strategy))

    strategy.harvest()
    sleep(chain)
    strategy.harvest()
    print("Want balance|strategy:", token.balanceOf(strategy))
    print("Want balance|vault:", token.balanceOf(vault))
    print("Assets:", strategy.estimatedTotalAssets().to("ether"))
    print("share price before:", vault.pricePerShare().to("ether"))
    print("vault info:", vault.strategies(strategy))

    strategy.harvest()
    # sleep(chain)
    # strategy.harvest()
    print("Want balance|strategy:", token.balanceOf(strategy))
    print("Want balance|vault:", token.balanceOf(vault))
    print("Assets:", strategy.estimatedTotalAssets().to("ether"))
    print("share price before:", vault.pricePerShare().to("ether"))
    print("vault info:", vault.strategies(strategy))

    after = strategy.estimatedTotalAssets()
    assert after > before
    print("share price after: ", vault.pricePerShare().to("ether"))
    print(f"implied apy: {(after / before - 1) / ((2*sample) / blocks_per_year):.5%}")
    # user withdraws all funds
    vault.withdraw(vault.balanceOf(whale), {"from": whale})
    assert token.balanceOf(whale) >= user_before


def test_strategy_withdraw(strategy, vault, token, whale, gov, chain):
    user_before = token.balanceOf(whale) + vault.balanceOf(whale)
    # token.approve(vault, token.balanceOf(whale), {"from": whale})
    vault.deposit(token.balanceOf(whale), {"from": whale})
    # first harvest adds initial deposits
    sleep(chain)
    strategy.harvest()
    initial_deposits = strategy.estimatedTotalAssets().to("ether")
    # second harvest secures some profits
    sleep(chain)
    strategy.harvest()
    sleep(chain)
    strategy.harvest()
    deposits_after_savings = strategy.estimatedTotalAssets().to("ether")
    assert deposits_after_savings > initial_deposits
    # user withdraws funds
    vault.withdraw(vault.balanceOf(whale), {"from": whale})
    assert token.balanceOf(whale) >= user_before
