# Decentralised Stable Coin

The system is designed to be as minimal as possible and have the tokens maitain a peg to the USD. It has the following properties:
- Collateral: Exogenous (backed by wETH & wBTC)
- Stability Mechanism: Algorithmic (people can mint the stablecoin by depositing collateral)
- Relative Stability: Pegged to USD (uses Chainlink for price feed)

It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC. This system is VERY loosely based on the MakerDAO system. It is not meant to be a 1:1 copy, but rather a simplified version that is easier to understand.

The system should always be overcollateralized. At no point should the value of all collateral be less than the $ backed value of all minted stablecoins.
