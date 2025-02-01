import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter
from datetime import datetime

# Constants matching Move implementation
OCTA = 100_000_000  # 10^8 for APT price scaling
INPUT_SCALE = 1_000_000  # 10^6 for overflow prevention
INITIAL_PRICE = 102_345_678  # 1 APT in OCTA units

# Updated weights for smoother progression
DEFAULT_WEIGHT_A = 350   # 1.25% in basis points - further reduced for smoother curve
DEFAULT_WEIGHT_B = 800    # 8% in basis points - reduced for gentler growth
DEFAULT_WEIGHT_C = 1     # Increased offset for smoother early progression
BPS = 10000  # 100% = 10000 basis points

def calculate_summation(n):
    """
    Calculate summation term: (n * (n + 1) * (2n + 1)) / 6
    Using strategic factoring to prevent overflow while maintaining precision
    """
    if n == 0:
        return 0
    
    # Calculate components
    two_n = 2 * n
    two_n_plus_1 = two_n + 1
    
    # Calculate (n + 1) * (2n + 1) = 2n^2 + 3n + 1
    n_squared = n * n
    two_n_squared = 2 * n_squared
    three_n = 3 * n
    inner_sum = two_n_squared + three_n + 1
    
    # Handle divisions strategically to minimize precision loss
    mut_inner_sum = inner_sum
    mut_n = n
    
    # Try to divide by 2 first if possible
    if mut_inner_sum % 2 == 0:
        mut_inner_sum = mut_inner_sum // 2
    elif mut_n % 2 == 0:
        mut_n = mut_n // 2
    
    # Try to divide by 3 if possible
    if mut_inner_sum % 3 == 0:
        mut_inner_sum = mut_inner_sum // 3
    elif mut_n % 3 == 0:
        mut_n = mut_n // 3
    
    # Multiply remaining terms
    mut_result = mut_n * mut_inner_sum
    
    # Apply any remaining divisions needed
    if inner_sum % 2 != 0 and n % 2 != 0:
        mut_result = mut_result // 2
    if inner_sum % 3 != 0 and n % 3 != 0:
        mut_result = mut_result // 3
    
    return mut_result

def calculate_single_pass_price(supply):
    """
    Calculate price for a single pass at a given supply level
    Returns the calculated price in OCTA units
    """
    # Early return for first purchase
    if supply == 0:
        return INITIAL_PRICE
    
    # Calculate n = s + c - 1
    s_plus_c = supply + DEFAULT_WEIGHT_C
    if s_plus_c <= 1:
        return INITIAL_PRICE
    n = s_plus_c - 1
    
    # Calculate summation at this supply level
    s = calculate_summation(n)
    
    # Apply weights directly without scaling
    weighted_a = (s * DEFAULT_WEIGHT_A) // BPS
    weighted_b = (weighted_a * DEFAULT_WEIGHT_B) // BPS
    
    # Scale to OCTA
    price = weighted_b * OCTA
    
    # Return at least initial price
    return max(INITIAL_PRICE, price)

def calculate_price(supply, amount, is_sell):
    """
    Calculate total price for buying/selling amount of passes at current supply
    Returns the calculated price in OCTA units
    """
    total_price = 0
    
    for i in range(amount):
        # For buys: calculate price at current supply level
        # For sells: calculate price at current supply level - 1
        if is_sell:
            # Prevent underflow for sells
            if supply <= i + 1:
                current_supply = 0  # Return initial price for selling last pass
            else:
                current_supply = supply - i - 1  # When selling, look at price at supply-1
        else:
            current_supply = supply + i  # When buying, look at price at current supply
        
        # Calculate price for this single pass
        pass_price = calculate_single_pass_price(current_supply)
        total_price += pass_price
    
    return total_price

def plot_bonding_curves():
    """
    Create 4 plots showing different supply ranges
    """
    ranges = [
        (0, 25, "First 25 Supply Points"),
        (0, 100, "First 100 Supply Points"),
        (0, 1000, "Supply Points up to 1,000"),
        (0, 10000, "Supply Points up to 10,000")
    ]
    
    for start, end, title in ranges:
        supplies = np.arange(start, end + 1)
        buy_prices = [calculate_price(s, 1, False) / OCTA for s in supplies]
        sell_prices = [calculate_price(s, 1, True) / OCTA for s in supplies]
        
        plt.figure(figsize=(12, 8))
        plt.plot(supplies, buy_prices, 'g-', label='Buy Price')
        plt.plot(supplies, sell_prices, 'r-', label='Sell Price')
        plt.title(f'Podium Protocol Bonding Curve\n{title}')
        plt.xlabel('Supply')
        plt.ylabel('Price (APT)')
        
        # Use scientific notation for y-axis on larger ranges
        if end > 100:
            plt.yscale('log')
            plt.grid(True, which="both", ls="-", alpha=0.2)
        else:
            plt.grid(True)
            
        plt.legend()
        
        # Save with range in filename
        filename = f'bonding_curve_{end}.png'
        plt.savefig(filename, dpi=300, bbox_inches='tight')
        plt.close()

def print_price_progression(max_supply=10):
    """
    Print detailed price progression up to max_supply
    """
    print("\n=== Price Progression ===")
    last_price = 0
    
    for supply in range(max_supply + 1):
        price = calculate_price(supply, 1, False)
        print(f"\nSupply: {supply}")
        print(f"Buy Price: {price/OCTA:.2f} APT ({price} OCTA)")
        
        if supply > 0:
            price_increase = price - last_price
            increase_percentage = (price_increase * 10000) // last_price if last_price > 0 else 0
            print(f"Price increase: {price_increase/OCTA:.2f} APT")
            print(f"Increase percentage: {increase_percentage/100:.2f}%")
        
        last_price = price

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

def analyze_key_price_points():
    """
    Analyze prices at key supply points to validate curve shape
    """
    key_points = [1, 5, 10, 25, 50, 75, 100, 150, 200, 500]
    
    print("\n=== Key Price Points Analysis ===")
    print("Supply | Buy Price (APT) | % Increase")
    print("-" * 45)
    
    last_price = INITIAL_PRICE
    for supply in key_points:
        price = calculate_price(supply, 1, False)
        price_in_apt = price / OCTA
        increase = ((price - last_price) / last_price * 100) if last_price > 0 else 0
        
        print(f"{supply:6d} | {price_in_apt:13.2f} | {increase:9.1f}%")
        last_price = price

def validate_early_accessibility():
    """
    Validate if early prices (first 15 passes) stay within target range
    Target: 1-10 APT for first 15 passes
    """
    print("\n=== Early Accessibility Check (First 15 Passes) ===")
    print("Pass # | Price (APT) | Within Target")
    print("-" * 45)
    
    for i in range(1, 16):
        price = calculate_price(i, 1, False) / OCTA
        within_target = 1 <= price <= 10
        print(f"{i:6d} | {price:10.2f} | {'✓' if within_target else '✗'}")

def analyze_price_bands():
    """
    Analyze price progression across different supply bands
    """
    print("\n=== Price Band Analysis ===")
    bands = [
        (1, 15, "Entry Band (1-15)"),
        (16, 50, "Growth Band (16-50)"),
        (51, 100, "Acceleration Band (51-100)"),
        (101, 500, "Exclusivity Band (101+)")
    ]
    
    for start, end, label in bands:
        prices = [calculate_price(i, 1, False) / OCTA for i in range(start, end + 1)]
        avg_price = sum(prices) / len(prices)
        min_price = min(prices)
        max_price = max(prices)
        avg_increase = (max_price - min_price) / min_price * 100
        
        print(f"\n{label}:")
        print(f"Average Price: {avg_price:.2f} APT")
        print(f"Price Range: {min_price:.2f} - {max_price:.2f} APT")
        print(f"Total Price Increase: {avg_increase:.1f}%")

def save_results_to_file(output):
    """
    Save analysis results to a file with timestamp and weight configuration
    """
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"BondingCurveTestingResults.txt"
    
    with open(filename, "a") as f:
        f.write("\n" + "="*80 + "\n")
        f.write(f"Test Run: {timestamp}\n")
        f.write(f"Weight Configuration:\n")
        f.write(f"WEIGHT_A: {DEFAULT_WEIGHT_A/100:.2f}% ({DEFAULT_WEIGHT_A} bps)\n")
        f.write(f"WEIGHT_B: {DEFAULT_WEIGHT_B/100:.2f}% ({DEFAULT_WEIGHT_B} bps)\n")
        f.write(f"WEIGHT_C: {DEFAULT_WEIGHT_C}\n")
        f.write(f"INITIAL_PRICE: {INITIAL_PRICE/OCTA:.2f} APT\n\n")
        f.write(output)
        f.write("\n" + "="*80 + "\n")

def capture_analysis():
    """
    Capture all analysis output for saving to file
    """
    import io
    from contextlib import redirect_stdout
    
    output = io.StringIO()
    with redirect_stdout(output):
        print("\n=== Key Price Points Analysis ===")
        print("Supply | Buy Price (APT) | % Increase")
        print("-" * 45)
        
        last_price = INITIAL_PRICE
        key_points = [1, 5, 10, 15, 25, 50, 75, 100, 150, 200, 500]
        for supply in key_points:
            price = calculate_price(supply, 1, False)
            price_in_apt = price / OCTA
            increase = ((price - last_price) / last_price * 100) if last_price > 0 else 0
            print(f"{supply:6d} | {price_in_apt:13.2f} | {increase:9.1f}%")
            last_price = price

        print("\n=== Early Accessibility Check (First 15 Passes) ===")
        print("Pass # | Price (APT) | Within Target")
        print("-" * 45)
        for i in range(1, 16):
            price = calculate_price(i, 1, False) / OCTA
            within_target = 1 <= price <= 10
            print(f"{i:6d} | {price:10.2f} | {'✓' if within_target else '✗'}")

        print("\n=== Price Band Analysis ===")
        bands = [
            (1, 15, "Entry Band (1-15)"),
            (16, 50, "Growth Band (16-50)"),
            (51, 100, "Acceleration Band (51-100)"),
            (101, 500, "Exclusivity Band (101+)")
        ]
        
        for start, end, label in bands:
            prices = [calculate_price(i, 1, False) / OCTA for i in range(start, end + 1)]
            avg_price = sum(prices) / len(prices)
            min_price = min(prices)
            max_price = max(prices)
            avg_increase = (max_price - min_price) / min_price * 100
            
            print(f"\n{label}:")
            print(f"Average Price: {avg_price:.2f} APT")
            print(f"Price Range: {min_price:.2f} - {max_price:.2f} APT")
            print(f"Total Price Increase: {avg_increase:.1f}%")
    
    return output.getvalue()

def main():
    # Print constants
    print("\nBonding Curve Configuration:")
    print(f"INITIAL_PRICE: {INITIAL_PRICE/OCTA:.2f} APT")
    print(f"DEFAULT_WEIGHT_A: {DEFAULT_WEIGHT_A/100:.2f}%")
    print(f"DEFAULT_WEIGHT_B: {DEFAULT_WEIGHT_B/100:.2f}%")
    print(f"DEFAULT_WEIGHT_C: {DEFAULT_WEIGHT_C}")
    
    # Run analysis
    analyze_key_price_points()
    validate_early_accessibility()
    analyze_price_bands()
    
    # Capture and save analysis
    results = capture_analysis()
    save_results_to_file(results)
    
    # Print results to console
    print(results)
    # Create plots
    plot_bonding_curves()

if __name__ == "__main__":
    main()


