import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter

# Constants based on the bonding curve implementation
DEFAULT_WEIGHT_A = 0.3 * 10**8  # Scaled by WAD
DEFAULT_WEIGHT_B = 0.2 * 10**8  # Scaled by WAD
DEFAULT_WEIGHT_C = 2
WAD = 10**8  # Adjusted scaling factor for precision
INITIAL_PRICE = 1 * WAD  # Ensure starting price is exactly 1

def get_price(supply, amount):
    # Adjusted supply
    adjusted_supply = supply + DEFAULT_WEIGHT_C

    # Calculate summations
    sum1 = ((adjusted_supply - 1) * adjusted_supply * (2 * (adjusted_supply - 1) + 1)) // 6
    sum2 = ((adjusted_supply - 1 + amount) * (adjusted_supply + amount) * (2 * (adjusted_supply - 1 + amount) + 1)) // 6

    # Summation difference
    summation = DEFAULT_WEIGHT_A * (sum2 - sum1)

    # Price calculation
    price = (DEFAULT_WEIGHT_B * summation * INITIAL_PRICE) // (WAD * WAD)

    # Return the maximum of calculated price and initial price
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

# Debugging: Print some price values
print("\nPrice values for the first few supplies:")
for i in range(20):
    print(f"Supply {i}: Price = {prices[i]:.2f} MOVE")

# Debugging: Print calculated prices for specific supply values
for supply in [1, 10, 25, 50, 100, 250, 500, 1000, 2000]:
    price = get_price(supply, 1) / WAD  # Convert to human-readable format
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
plt.savefig('bonding_curve.png')  # Save the plot as a PNG file


