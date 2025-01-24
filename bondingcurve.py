import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter

# Constants for bonding curve calculations - exactly matching Move implementation
INPUT_SCALE = 1000  # 10^3 for input scaling
WAD = 100000000    # 10^8 (1 APT)
INITIAL_PRICE = WAD # 1 APT
DEFAULT_WEIGHT_A = 30000000  # 0.3 * 10^8
DEFAULT_WEIGHT_B = 20000000  # 0.2 * 10^8
DEFAULT_WEIGHT_C = 2

def get_price(supply, amount, debug=False):
    # Add adjustment factor to supply
    adjusted_supply = supply + DEFAULT_WEIGHT_C
    if adjusted_supply == 0:
        return INITIAL_PRICE

    n1 = adjusted_supply - 1
    
    # Scale down early to prevent overflow - exactly like Move
    scaled_n1 = n1 // INPUT_SCALE
    scaled_supply = adjusted_supply // INPUT_SCALE
    
    # Calculate first sum with scaled values
    sum1 = (scaled_n1 * scaled_supply * (2 * scaled_n1 + 1)) // 6
    
    # Calculate second summation with scaled values - match Move exactly
    scaled_amount = amount // INPUT_SCALE
    n2 = scaled_n1 + scaled_amount
    sum2 = (n2 * (scaled_supply + scaled_amount) * (2 * n2 + 1)) // 6
    
    # Calculate summation difference
    summation_diff = sum2 - sum1
    
    # Apply weights in parts with intermediate scaling - match Move exactly
    step1 = (summation_diff * (DEFAULT_WEIGHT_A // INPUT_SCALE)) // WAD
    step2 = (step1 * (DEFAULT_WEIGHT_B // INPUT_SCALE)) // WAD
    
    # Final price calculation - match Move exactly
    # Don't multiply by INITIAL_PRICE since it's already in WAD units
    price = step2

    if debug:
        print(f"\nCalculation steps:")
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
    # Use raw supply numbers, but each increment represents 1 APT (WAD units)
    price = get_price(supply, WAD, debug=(i < 3))  # amount = 1 APT = WAD
    print(f"Supply {supply/WAD:.8f}: Price = {price/WAD:.8f} APT")
    supply += WAD  # Increment by 1 APT worth of supply

# Calculate prices for plotting
supply_range = np.arange(0, 101, 1)
prices = []
for supply in supply_range:
    # Convert supply to WAD units
    supply_in_wad = supply * WAD
    # Amount should be WAD (1 APT)
    price = get_price(supply_in_wad, WAD) / WAD
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

def print_price_analysis(supply, amount_in_apt):
    # Convert supply and amount to WAD units
    supply_in_wad = supply * WAD
    amount_in_wad = amount_in_apt * WAD
    
    # Get price in WAD units
    price_in_units = get_price(supply_in_wad, amount_in_wad)
    price_in_apt = price_in_units / WAD  # Convert to Move units
    
    # Calculate fees in APT (using integer division like Move)
    protocol_fee = (price_in_units * 4) // 100 / WAD  # 4%
    subject_fee = (price_in_units * 8) // 100 / WAD   # 8%
    total_cost = price_in_apt + protocol_fee + subject_fee
    
    fees = {
        'base_price': price_in_apt,
        'protocol_fee': protocol_fee,
        'subject_fee': subject_fee,
        'total_cost': total_cost
    }
    return fees

print("\nPurchase Analysis (in whole APT):")
supply = 0
for i in range(5):
    # Testing with 1 APT purchase each time
    fees = print_price_analysis(supply, 1)
    print(f"\nPurchase {i+1}:")
    print(f"Supply: {supply:.8f} APT")
    print(f"Base Price: {fees['base_price']:.8f} APT")
    print(f"Protocol Fee: {fees['protocol_fee']:.8f} APT")
    print(f"Subject Fee: {fees['subject_fee']:.8f} APT")
    print(f"Total Cost: {fees['total_cost']:.8f} APT")
    supply += 1  # Increment by 1 APT


