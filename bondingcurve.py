import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter

# Constants - exactly matching Move implementation
OCTA = 100000000        # 10^8 for APT price scaling
INPUT_SCALE = 1000000   # 10^6 for overflow prevention
DEFAULT_WEIGHT_A = 40000 # 400 in basis points
DEFAULT_WEIGHT_B = 30000 # 300 in basis points
DEFAULT_WEIGHT_C = 2    # Constant offset
BPS = 10000            # 100% = 10000 basis points
INITIAL_PRICE = OCTA   # 1 APT in OCTA units

def calculate_summation(n):
    """Helper function to calculate summation term: (n * (n + 1) * (2n + 1)) / 6"""
    if n == 0:
        return 0
    n_plus_1 = n + 1
    two_n_plus_1 = 2 * n + 1
    return (n * n_plus_1 * two_n_plus_1) // 6

def calculate_price(supply, amount, is_sell, debug=False):
    """
    Supply and amount should be in OCTA units (10^8)
    Returns price in OCTA units
    """
    if debug:
        print("\n=== Starting price calculation ===")
        print(f"Supply: {supply}")
        print(f"Amount: {amount}")
        print(f"Is sell: {is_sell}")

    if supply == 0:
        if debug:
            print("First purchase - returning initial price")
        return INITIAL_PRICE

    # Calculate n1 = (s + c - 1) / k
    s_plus_c = supply + DEFAULT_WEIGHT_C
    if s_plus_c <= 1:
        if debug:
            print("Supply + C <= 1 - returning initial price")
        return INITIAL_PRICE
    n1 = (s_plus_c - 1) // INPUT_SCALE
    
    # Calculate n2 based on buy/sell
    if is_sell:
        supply_minus_amount = max(s_plus_c - amount, 1)
        n2 = (supply_minus_amount - 1) // INPUT_SCALE
    else:
        n2 = (s_plus_c + amount - 1) // INPUT_SCALE

    if debug:
        print(f"n1: {n1}")
        print(f"n2: {n2}")

    # Calculate summations
    s1 = calculate_summation(n1)
    s2 = calculate_summation(n2)
    
    if debug:
        print(f"s1: {s1}")
        print(f"s2: {s2}")

    # Calculate difference
    s_diff = s2 - s1 if s2 > s1 else (s1 - s2 if is_sell else 0)
    
    if debug:
        print(f"s_diff: {s_diff}")

    # Apply weights
    step1 = (s_diff * DEFAULT_WEIGHT_A) // BPS
    step2 = (step1 * DEFAULT_WEIGHT_B) // BPS
    
    if debug:
        print(f"step1: {step1}")
        print(f"step2: {step2}")

    # Return at least initial price
    final_price = max(step2, INITIAL_PRICE)
    
    if debug:
        print(f"final_price: {final_price}")
        print("=== End price calculation ===\n")

    return final_price

def print_price_analysis(supply, amount_in_apt):
    """
    Calculates and returns a breakdown of prices and fees for a purchase
    
    Args:
        supply: Current supply in APT
        amount_in_apt: Amount to purchase in APT
    
    Returns:
        Dictionary containing base_price, protocol_fee, subject_fee, and total_cost (all in APT)
    """
    # Convert supply and amount to OCTA units
    supply_in_octa = supply * OCTA
    amount_in_octa = amount_in_apt * OCTA
    
    # Get price in OCTA units
    price_in_octa = calculate_price(supply_in_octa, amount_in_octa, False)
    
    # Convert all values from OCTA to APT for display
    price_in_apt = price_in_octa / OCTA
    protocol_fee = (price_in_octa * 4) // 100 / OCTA  # 4%
    subject_fee = (price_in_octa * 8) // 100 / OCTA   # 8%
    total_cost = price_in_apt + protocol_fee + subject_fee
    
    fees = {
        'base_price': price_in_apt,
        'protocol_fee': protocol_fee,
        'subject_fee': subject_fee,
        'total_cost': total_cost
    }
    return fees

# Print the constants
print(f"\nConstants:")
print(f"INPUT_SCALE: {INPUT_SCALE}")
print(f"OCTA: {OCTA}")
print(f"INITIAL_PRICE: {INITIAL_PRICE}")
print(f"DEFAULT_WEIGHT_A: {DEFAULT_WEIGHT_A}")
print(f"DEFAULT_WEIGHT_B: {DEFAULT_WEIGHT_B}")
print(f"DEFAULT_WEIGHT_C: {DEFAULT_WEIGHT_C}")
print(f"BPS: {BPS}")

# Calculate and print prices for first 20 purchases
print("\nPrice Progression (Base Price Only - No Fees)")
print("This shows how the base price changes as supply increases")
print("Supply format: current_supply -> price for next purchase")
print("----------------------------------------------------")
supply = 0
for i in range(20):
    supply_in_octa = supply * OCTA
    price = calculate_price(supply_in_octa, OCTA, False, debug=(i < 3))
    print(f"At supply {supply} APT -> Next purchase price = {price/OCTA:.8f} APT")
    supply += 1

print("\n\nDetailed Purchase Analysis (Including All Fees)")
print("This shows the complete cost breakdown for each purchase")
print("Supply shows the current supply before the purchase")
print("----------------------------------------------------")
supply = 0
for i in range(5):
    fees = print_price_analysis(supply, 1)
    print(f"\nPurchase #{i+1}:")
    print(f"Current Supply: {supply:.8f} APT")
    print(f"Purchase Amount: 1.00000000 APT")
    print(f"Base Price: {fees['base_price']:.8f} APT")
    print(f"+ Protocol Fee (4%): {fees['protocol_fee']:.8f} APT")
    print(f"+ Subject Fee (8%): {fees['subject_fee']:.8f} APT")
    print(f"= Total Cost: {fees['total_cost']:.8f} APT")
    print(f"New Supply After Purchase: {supply + 1:.8f} APT")
    supply += 1

# Test buy/sell comparison at a specific supply point
print("\n\nBuy/Sell Price Comparison")
print("This shows the price difference between buying and selling at the same supply point")
print("----------------------------------------------------")
test_supply = 5
buy_price = calculate_price(test_supply * OCTA, OCTA, False, debug=True)
sell_price = calculate_price(test_supply * OCTA, OCTA, True, debug=True)
print(f"\nCurrent circulation: {test_supply} tokens")
print(f"Cost to buy 1 more token: {buy_price/OCTA:.8f} APT")
print(f"APT received for selling 1 token: {sell_price/OCTA:.8f} APT")
print(f"Buy/Sell difference: {(buy_price - sell_price)/OCTA:.8f} APT")
print(f"Buy/Sell spread: {((buy_price - sell_price) * 100 / buy_price):.2f}%")
print(f"After buying 1 token, circulation would be: {test_supply + 1} tokens")
print(f"After selling 1 token, circulation would be: {test_supply - 1} tokens")

# Add price statistics with more context
print("\n\nBonding Curve Statistics")
print("This shows key price points across the supply range")
print("----------------------------------------------------")
supply_range = np.arange(0, 101, 1)
prices = []
for supply in supply_range:
    price = calculate_price(supply * OCTA, OCTA, False)
    prices.append(price/OCTA)

print(f"Initial Price (0 supply): {prices[0]:.8f} APT")
print(f"Price at 10 APT supply: {prices[10]:.8f} APT")
print(f"Price at 50 APT supply: {prices[50]:.8f} APT")
print(f"Price at 100 APT supply: {prices[100]:.8f} APT")
print(f"Minimum Price: {min(prices):.8f} APT")
print(f"Maximum Price: {max(prices):.8f} APT")
print(f"Average Price: {sum(prices)/len(prices):.8f} APT")
print(f"Price increase from 0 to 100: {((prices[100]/prices[0])-1)*100:.2f}%")

# Create the plot with more detailed labels
plt.figure(figsize=(12, 8))
plt.plot(supply_range, prices, 'b-', label='Price vs Supply')
plt.xlabel('Supply (APT)')
plt.ylabel('Price (APT)')
plt.title('Bonding Curve: Price vs Supply\nShows how price changes as supply increases')
plt.grid(True)
plt.legend()
plt.savefig('bonding_curve.png')
plt.close()


