import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter

# Constants for bonding curve calculations - exactly matching Move implementation
INPUT_SCALE = 1000  # 10^3 for input scaling
WAD = 100000000    # 10^8 for price calculations
INITIAL_PRICE = 100000000  # 1 * 10^8 (same as WAD)
DEFAULT_WEIGHT_A = 30000000  # 0.3 * 10^8
DEFAULT_WEIGHT_B = 20000000  # 0.2 * 10^8
DEFAULT_WEIGHT_C = 2  # Adjustment factor

def get_price(supply, amount, debug=False):
    # Add adjustment factor to supply
    adjusted_supply = supply + DEFAULT_WEIGHT_C
    if adjusted_supply == 0:
        return INITIAL_PRICE

    # Calculate first summation in parts to prevent overflow
    n1 = adjusted_supply - 1
    
    # Scale down early to prevent overflow
    scaled_n1 = n1 // INPUT_SCALE
    scaled_supply = adjusted_supply // INPUT_SCALE
    
    # Calculate first sum with scaled values
    sum1 = (scaled_n1 * scaled_supply * (2 * scaled_n1 + 1)) // 6
    
    # Calculate second summation with scaled values
    scaled_amount = amount // INPUT_SCALE
    n2 = scaled_n1 + scaled_amount
    sum2 = (n2 * (scaled_supply + scaled_amount) * (2 * n2 + 1)) // 6
    
    # Calculate summation difference
    summation_diff = sum2 - sum1
    
    # Apply weights in parts with intermediate scaling
    step1 = (summation_diff * (DEFAULT_WEIGHT_A // INPUT_SCALE)) // WAD
    step2 = (step1 * (DEFAULT_WEIGHT_B // INPUT_SCALE)) // WAD
    
    # Scale up the final result
    price = step2 * INITIAL_PRICE

    if debug:
        print(f"\nCalculation for supply={supply}, amount={amount}:")
        print(f"adjusted_supply: {adjusted_supply}")
        print(f"n1: {n1}")
        print(f"scaled_n1: {scaled_n1}")
        print(f"scaled_supply: {scaled_supply}")
        print(f"sum1: {sum1}")
        print(f"n2: {n2}")
        print(f"sum2: {sum2}")
        print(f"summation_diff: {summation_diff}")
        print(f"step1: {step1}")
        print(f"step2: {step2}")
        print(f"final_price: {price}")
        print(f"final_price_in_APT: {price/WAD}")
    
    return max(price, INITIAL_PRICE)

# Print the constants
print(f"\nConstants:")
print(f"INPUT_SCALE: {INPUT_SCALE}")
print(f"WAD: {WAD}")
print(f"INITIAL_PRICE: {INITIAL_PRICE}")
print(f"DEFAULT_WEIGHT_A: {DEFAULT_WEIGHT_A}")
print(f"DEFAULT_WEIGHT_B: {DEFAULT_WEIGHT_B}")
print(f"DEFAULT_WEIGHT_C: {DEFAULT_WEIGHT_C}")

# Calculate and print prices for first 20 purchases
print("\nPrice progression for first 20 purchases:")
supply = 0
for i in range(20):
    # Only show debug info for first 3 purchases
    price = get_price(supply, 1, debug=(i < 3))
    print(f"Supply {supply}: Price = {price/WAD:.8f} APT")
    supply += 1

# Calculate prices for plotting
supply_range = np.arange(0, 101, 1)
prices = []
for supply in supply_range:
    price = get_price(supply, 1) / WAD
    prices.append(price)

# Create the plot
plt.figure(figsize=(12, 8))
plt.plot(supply_range, prices, 'b-', label='Price vs Supply')
plt.xlabel('Supply')
plt.ylabel('Price (in APT)')
plt.title('Bonding Curve: Price vs Supply')
plt.grid(True)
plt.legend()

# Print key statistics
print(f"\nPrice Statistics:")
print(f"Min Price: {min(prices):.8f} APT")
print(f"Max Price: {max(prices):.8f} APT")
print(f"Price at Supply 50: {prices[50]:.8f} APT")
print(f"Price at Supply 100: {prices[100]:.8f} APT")

plt.savefig('bonding_curve.png')
plt.close()


