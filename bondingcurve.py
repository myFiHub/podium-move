import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter

# Constants based on the bonding curve implementation
DEFAULT_WEIGHT_A = 30000000  # 0.3 * 10^8
DEFAULT_WEIGHT_B = 20000000  # 0.2 * 10^8
DEFAULT_WEIGHT_C = 2
WAD = 100000000  # 10^8 (SCALING_FACTOR)
INITIAL_PRICE = 1 * WAD  # Ensure starting price is exactly 1

def get_price(supply, amount):
    # Add adjustment factor to supply
    adjusted_supply = supply + DEFAULT_WEIGHT_C
    if adjusted_supply == 0:
        return INITIAL_PRICE

    # Calculate summations
    n1 = adjusted_supply - 1
    
    # Calculate first summation
    # Divide operations into steps to prevent overflow
    sum1_part1 = n1 * adjusted_supply
    sum1_part2 = (2 * n1 + 1)
    sum1 = (sum1_part1 * sum1_part2) // 6
    
    # Calculate summation for supply + amount
    n2 = n1 + amount
    sum2_part1 = n2 * (adjusted_supply + amount)
    sum2_part2 = (2 * n2 + 1)
    sum2 = (sum2_part1 * sum2_part2) // 6
    
    # Calculate final price with intermediate scaling to prevent overflow
    summation = DEFAULT_WEIGHT_A * (sum2 - sum1)
    price = ((DEFAULT_WEIGHT_B * summation) // WAD * INITIAL_PRICE) // WAD
    
    return max(price, INITIAL_PRICE)

# Print the constants
print(f"DEFAULT_WEIGHT_A: {DEFAULT_WEIGHT_A}")
print(f"DEFAULT_WEIGHT_B: {DEFAULT_WEIGHT_B}")
print(f"DEFAULT_WEIGHT_C: {DEFAULT_WEIGHT_C}")
print(f"WAD: {WAD}")
print(f"INITIAL_PRICE: {INITIAL_PRICE}")

# Calculate prices for plotting
supply_range = np.arange(0, 2001, 1)
prices = []
for supply in supply_range:
    price = get_price(supply, 1) / WAD  # Convert to human-readable format
    prices.append(price)

# Print first 20 prices
print("\nPrice values for the first 20 supplies:")
for i in range(20):
    print(f"Supply {i}: Price = {prices[i]:.2f} MOVE")



# Print calculated prices for key supply points
print("\nPrices at key supply points:")
for supply in [1, 10, 25, 50, 100, 250, 500, 1000, 2000]:
    price = get_price(supply, 1) / WAD
    print(f"Supply {supply}: Price = {price:.2f} MOVE")

# Create the plot
plt.figure(figsize=(12, 8))
plt.plot(supply_range, prices, 'b-', label='Price vs Supply')
plt.xlabel('Supply')
plt.ylabel('Price (in MOVE)')
plt.title('Bonding Curve: Price vs Supply')

# Set y-axis to display whole numbers with commas
plt.gca().yaxis.set_major_formatter(FuncFormatter(lambda x, _: f'{int(x):,}'))

plt.grid(True)
plt.legend()

# Add some statistics
print(f"\nPrice Statistics:")
print(f"Min Price: {min(prices):.2f} MOVE")
print(f"Max Price: {max(prices):.2f} MOVE")
print(f"Price at Supply 1000: {prices[1000]:.2f} MOVE")
print(f"Price at Supply 2000: {prices[2000]:.2f} MOVE")

# Save the plot to a file
plt.savefig('bonding_curve.png')


