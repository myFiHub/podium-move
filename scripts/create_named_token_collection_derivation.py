from sha3 import keccak_256
import binascii

def debug_bytes(label, b):
    print(f"{label}: 0x{binascii.hexlify(b).decode()}")

def create_token_seed(collection_name: bytes, token_name: bytes) -> bytes:
    """Mimics token::create_token_seed"""
    seed = collection_name + b"::" + token_name
    debug_bytes("Token seed", seed)
    return seed

def create_object_address(creator: bytes, seed: bytes) -> str:
    """Mimics object::create_object_address"""
    final_bytes = creator + seed
    debug_bytes("Final bytes for object", final_bytes)
    addr = keccak_256(final_bytes).hexdigest()
    return f"0x{addr}"

def create_collection_address(creator: bytes, collection_name: bytes) -> str:
    """Mimics collection::create_collection_address"""
    final_bytes = creator + collection_name
    debug_bytes("Final bytes for collection", final_bytes)
    addr = keccak_256(final_bytes).hexdigest()
    return f"0x{addr}"

def main():
    # Input parameters from debug output
    creator = bytes.fromhex("321")  # @0x321
    collection_name = b"PodiumOutposts"
    token_name = b"Test Outpost"

    print("\n=== Token Address Calculation ===")
    # Calculate token address
    seed = create_token_seed(collection_name, token_name)
    token_addr = create_object_address(creator, seed)
    print(f"Calculated token address: {token_addr}")
    print(f"Debug output token addr: @0x8c26c6afa7b498be26b97d639837aff1be8dd88ef78b61f9bc914408ab6f346c")

    print("\n=== Collection Address Calculation ===")
    # Calculate collection address
    collection_addr = create_collection_address(creator, collection_name)
    print(f"Calculated collection address: {collection_addr}")
    print(f"Debug output collection addr: @0x6b173ee689954d7217401e69d9933306f6f29ad05bf1a3f01ca6d25fd29dbf19")

if __name__ == "__main__":
    main()