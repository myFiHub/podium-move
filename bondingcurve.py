import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter
from datetime import datetime
from scipy.optimize import minimize
from scipy.stats import norm
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import RBF, ConstantKernel as C

# Constants matching Move implementation
OCTA = 100_000_000  # 10^8 for APT price scaling
INPUT_SCALE = 1_000_000  # 10^6 for overflow prevention
INITIAL_PRICE = 100_000_000  # 1 APT in OCTA units
BPS = 10000  # 100% = 10000 basis points

# Target prices at key supply points with detailed rationale
TARGET_PRICES = {
    1: 1.0,      # Supply 1: 1 APT – Ultra-accessible founder entry
    5: 2.5,      # Supply 5: 2.5 APT – Very early adopter rate
    10: 5.0,     # Supply 10: 5 APT – Early adopter premium
    15: 8.0,     # Supply 15: 8 APT – Core community rate
    25: 20.0,    # Supply 25: 20 APT – Growth phase begins
    50: 75.0,    # Supply 50: 75 APT – Premium phase
    75: 150.0,   # Supply 75: 150 APT – Exclusivity phase
    100: 200.0   # Supply 100: 200 APT – Final premium phase
}

# Phase definitions for weighted optimization
PHASES = {
    'early': (1, 15),    # Early adopter phase
    'growth': (16, 25),  # Growth phase
    'premium': (26, 50), # Premium phase
    'exclusive': (51, 100) # Exclusivity phase
}

class BondingCurveOptimizer:
    def __init__(self):
        self.best_score = float('inf')
        self.best_weights = None
        self.history = []
        
    def objective_function(self, weights):
        """
        Calculate how well the weights achieve our target goals
        Lower score is better
        """
        weight_a, weight_b, weight_c = weights
        
        # Enforce constraints
        if not (100 <= weight_a <= 5000 and 100 <= weight_b <= 5000 and 1 <= weight_c <= 10):
            return float('inf')
        
        # Set weights for calculation
        global DEFAULT_WEIGHT_A, DEFAULT_WEIGHT_B, DEFAULT_WEIGHT_C
        DEFAULT_WEIGHT_A = int(weight_a)
        DEFAULT_WEIGHT_B = int(weight_b)
        DEFAULT_WEIGHT_C = int(weight_c)
        
        # Calculate errors for target points with phase-based weighting
        total_error = 0
        phase_errors = {phase: 0 for phase in PHASES.keys()}
        
        for supply, target_price in TARGET_PRICES.items():
            actual_price = calculate_price(supply, 1, False) / OCTA
            error = abs(actual_price - target_price)
            error_ratio = abs(actual_price / target_price - 1)
            
            # Weight errors by phase and add extra weight for supply=100
            if supply <= 15:
                phase_errors['early'] += error_ratio ** 2 * 2.0  # Higher weight for early phase accuracy
            elif supply <= 25:
                phase_errors['growth'] += error_ratio ** 2 * 1.5
            elif supply <= 50:
                phase_errors['premium'] += error_ratio ** 2 * 1.2
            else:
                # Extra weight for supply=100 target
                if supply == 100:
                    phase_errors['exclusive'] += error_ratio ** 2 * 3.0  # Increased weight for supply=100
                else:
                    phase_errors['exclusive'] += error_ratio ** 2
        
        # Add phase errors to total
        total_error = sum(phase_errors.values())
        
        # Penalties for constraint violations
        penalties = 0
        
        # Strong penalty for early prices being too high
        for supply in range(1, 16):
            price = calculate_price(supply, 1, False) / OCTA
            if price > TARGET_PRICES.get(supply, 8.0):  # Use 8.0 as default cap for early phase
                penalties += (price - TARGET_PRICES.get(supply, 8.0)) ** 2 * 2.0
        
        # Penalty for incorrect price progression (ensure monotonic increase)
        last_price = 0
        for supply in sorted(TARGET_PRICES.keys()):
            price = calculate_price(supply, 1, False) / OCTA
            if price <= last_price and supply > 1:  # Allow first price to be equal
                penalties += (last_price - price + 0.1) ** 2 * 1.5
            last_price = price
        
        # Strong penalty for price at supply 100 being outside target range
        price_100 = calculate_price(100, 1, False) / OCTA
        if price_100 < 100 or price_100 > 250:  # Enforce strict range for supply=100
            penalties += ((price_100 - 200) / 200) ** 2 * 5.0  # Increased penalty weight
        
        # Calculate smoothness penalty
        smoothness_penalty = 0
        for i in range(1, 100):
            price_i = calculate_price(i, 1, False) / OCTA
            price_next = calculate_price(i + 1, 1, False) / OCTA
            if price_next - price_i > price_i:  # More than 100% increase
                smoothness_penalty += ((price_next - price_i) / price_i - 1) ** 2
        
        score = total_error + penalties + smoothness_penalty * 0.5
        
        # Store if best so far
        if score < self.best_score:
            self.best_score = score
            self.best_weights = weights
            self.save_weight_results(weights, score)
        
        return score
    
    def save_weight_results(self, weights, score):
        """Save the results of a weight configuration"""
        weight_a, weight_b, weight_c = weights
        
        # Set weights for analysis
        global DEFAULT_WEIGHT_A, DEFAULT_WEIGHT_B, DEFAULT_WEIGHT_C
        DEFAULT_WEIGHT_A = int(weight_a)
        DEFAULT_WEIGHT_B = int(weight_b)
        DEFAULT_WEIGHT_C = int(weight_c)
        
        # Capture analysis
        results = capture_analysis()
        
        # Add optimization details
        optimization_info = f"\nOptimization Score: {score:.6f}\n"
        results = optimization_info + results
        
        # Save to file
        save_results_to_file(results)
        
        # Store in history
        self.history.append({
            'weights': weights,
            'score': score
        })
    
    def bayesian_optimization(self, n_iterations=50):
        """
        Perform Bayesian optimization to find optimal weights
        """
        # Define bounds for weights
        bounds = [(100, 5000), (100, 5000), (1, 10)]
        
        # Initialize with random points
        n_random = 10
        X = np.random.uniform(
            low=[b[0] for b in bounds],
            high=[b[1] for b in bounds],
            size=(n_random, 3)
        )
        y = np.array([self.objective_function(x) for x in X])
        
        # Gaussian Process with custom kernel
        kernel = C(1.0) * RBF([100.0, 100.0, 1.0])
        gp = GaussianProcessRegressor(kernel=kernel, n_restarts_optimizer=10)
        
        for i in range(n_iterations):
            # Fit GP
            gp.fit(X, y)
            
            # Define acquisition function (Expected Improvement)
            def expected_improvement(x):
                x = x.reshape(1, -1)
                mu, sigma = gp.predict(x, return_std=True)
                
                # Find best observed value
                y_best = np.min(y)
                
                # Calculate improvement
                imp = y_best - mu
                Z = imp / sigma
                ei = imp * norm.cdf(Z) + sigma * norm.pdf(Z)
                
                return -ei
            
            # Find next point to evaluate
            x_next = minimize(
                expected_improvement,
                X[np.argmin(y)],
                bounds=bounds,
                method='L-BFGS-B'
            ).x
            
            # Evaluate point
            y_next = self.objective_function(x_next)
            
            # Add to observed data
            X = np.vstack((X, x_next))
            y = np.append(y, y_next)
            
            print(f"\nIteration {i+1}/{n_iterations}")
            print(f"Best score so far: {self.best_score:.6f}")
            print(f"Best weights: A={self.best_weights[0]:.0f}, B={self.best_weights[1]:.0f}, C={self.best_weights[2]:.1f}")
        
        return self.best_weights, self.best_score

def optimize_weights():
    """Run the optimization process"""
    optimizer = BondingCurveOptimizer()
    best_weights, best_score = optimizer.bayesian_optimization(n_iterations=50)
    
    print("\nOptimization Complete!")
    print(f"Best score: {best_score:.6f}")
    print(f"Best weights found:")
    print(f"WEIGHT_A: {best_weights[0]:.0f} ({best_weights[0]/100:.2f}%)")
    print(f"WEIGHT_B: {best_weights[1]:.0f} ({best_weights[1]/100:.2f}%)")
    print(f"WEIGHT_C: {best_weights[2]:.1f}")
    
    return best_weights

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
    # Run optimization
    best_weights = optimize_weights()
    
    # Set best weights for final analysis
    global DEFAULT_WEIGHT_A, DEFAULT_WEIGHT_B, DEFAULT_WEIGHT_C
    DEFAULT_WEIGHT_A = int(best_weights[0])
    DEFAULT_WEIGHT_B = int(best_weights[1])
    DEFAULT_WEIGHT_C = best_weights[2]
    
    # Print final analysis
    print("\nFinal Analysis with Best Weights:")
    print(f"INITIAL_PRICE: {INITIAL_PRICE/OCTA:.2f} APT")
    print(f"DEFAULT_WEIGHT_A: {DEFAULT_WEIGHT_A/100:.2f}%")
    print(f"DEFAULT_WEIGHT_B: {DEFAULT_WEIGHT_B/100:.2f}%")
    print(f"DEFAULT_WEIGHT_C: {DEFAULT_WEIGHT_C}")
    
    # Run and save final analysis
    results = capture_analysis()
    save_results_to_file(results)
    print(results)
    
    # Create plots
    plot_bonding_curves()

if __name__ == "__main__":
    main()


