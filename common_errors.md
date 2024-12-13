# Common Errors in Move Development

## Type System Errors

### 1. Object Ownership Verification
```move
// ❌ Incorrect: Missing type parameter and wrong argument type
object::owns(collection_addr, signer_addr)

// ✅ Correct: Proper type parameter and object reference
object::owns<Collection>(
    object::address_to_object<Collection>(collection_addr),
    signer_addr
)
```
- Error: `incompatible types` and `cannot infer type`
- Issue: `owns` function expects an `Object<T>` type and needs explicit type parameter
- Solution: 
  1. Provide explicit type parameter to `owns`
  2. Convert address to object using `address_to_object`
  3. Ensure proper object type is used

### 2. Object Existence Verification
```move
// Common pattern for checking object existence
assert!(object::is_object(addr), error::not_found(EOBJECT_DOES_NOT_EXIST));
```
- Error: `EOBJECT_DOES_NOT_EXIST (393218)`
- Issue: Attempting to convert an address to an object when no ObjectCore exists
- Solution: Always verify object existence before operations

### 3. Collection Existence Verification
```move
// ❌ Incorrect: Using non-existent function
assert!(collection::exists_at(collection_addr), error::not_found(ECOLLECTION_NOT_FOUND));

// ✅ Correct: Use object existence check
assert!(object::is_object(collection_addr), error::not_found(ECOLLECTION_NOT_FOUND));
```
- Error: `unbound module member` - Invalid module access. Unbound function 'exists_at' in module 'collection'
- Issue: The `exists_at` function doesn't exist in the collection module
- Solution: Use `object::is_object()` to verify collection existence

## Token Operation Errors

### 1. Incorrect Token URI Update
```
error[E04017]: too many arguments
error[E04007]: incompatible types
    token::set_uri(owner, outpost, new_uri);
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    Invalid call of 'token::set_uri'. The call expected 2 argument(s) but got 3
```
**Issue**: Attempting to call `token::set_uri` with wrong parameters
**Solution**: Use proper token mutator reference:
```move
// ❌ Incorrect: Wrong parameter types and count
token::set_uri(owner, outpost, new_uri);

// ✅ Correct: Use mutator reference
let mutator_ref = token::generate_mutator_ref(&token);
token::set_uri(&mutator_ref, new_uri);
```

## Struct Visibility Errors

### 1. Invalid Field Access in Tests
```
error[E04001]: restricted visibility
    assert!(event.creator == signer::address_of(user1), 5002);
            ^^^^^^^^^^^^^ Invalid access of field 'creator'
```
**Solutions**:
1. Add public accessor functions in the module:
```move
// In module
public fun get_creator(event: &OutpostCreatedEvent): address {
    event.creator
}

// In test
assert!(PodiumOutpost::get_creator(event) == signer::address_of(user1), 5002);
```

2. Or make fields public:
```move
struct OutpostCreatedEvent has drop, store {
    public creator: address,
    public outpost_name: String,
    // ...
}
```

## Address Resolution Errors

### 1. Unassigned Named Addresses
```
error[E03001]: address with no value
    assert!(signer::address_of(admin) == @podium_admin, ENOT_ADMIN);
                                        ^^^^^^^^^^^^ address 'podium_admin' is not assigned a value
```
**Solutions**:
1. Add address to Move.toml:
```toml
[addresses]
podium_admin = "0x123"  # Replace with actual address

[dev-addresses]
podium_admin = "0x123"  # For test environment
```

2. Or use a constant:
```move
const PODIUM_ADMIN: address = @0x123;
```

## Import Management Errors

### 1. Duplicate Module Imports
```
error[E02001]: duplicate declaration, item, or annotation
    use podium::PodiumOutpost;
    use podium::PodiumOutpost::{Self, OutpostData};
        ^^^^^^^^^^^^^ Duplicate module alias 'PodiumOutpost'
```
**Solution**: Combine imports or use specific ones:
```move
// ✅ Correct: Combined import
use podium::PodiumOutpost::{Self, OutpostData};

// ✅ Alternative: Specific imports
use podium::PodiumOutpost;
use podium::PodiumOutpost::OutpostData;
```

### 2. Unbound Field Errors
```
error[E03010]: unbound field
    outpost_data.fee_share = new_fee_share;
    ^^^^^^^^^^^^^^^^^^^^^^ Unbound field 'fee_share'
```
**Solution**: Ensure field exists in struct definition:
```move
struct OutpostData has key {
    fee_share: u64,
    // ... other fields
}
```

## Function Naming Alignment

### 1. Test/Implementation Mismatch
```
error[E03003]: unbound module member
    PodiumOutpost::update_metadata_uri(user1, outpost, new_uri);
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Invalid module access
```
**Solution**: Align function names between tests and implementation:
```move
// In implementation
public entry fun set_metadata_uri(owner: &signer, ...) { ... }

// In tests
PodiumOutpost::set_metadata_uri(user1, ...);
```

## Best Practices Updates:

1. **Token Operations**:
   - Always use proper mutator references
   - Verify token existence before operations
   - Follow token standard patterns

2. **Struct Visibility**:
   - Use public accessor functions for private fields
   - Document field visibility requirements
   - Consider test requirements when designing structs

3. **Address Management**:
   - Define all named addresses in Move.toml
   - Use constants for fixed addresses
   - Document address requirements

4. **Import Organization**:
   - Group imports by module source
   - Avoid duplicate imports
   - Remove unused imports
   - Use specific imports over wildcards

# Common Errors in PodiumOutpost Development

## Error Category 1: Function Naming and Visibility
### Error: Inconsistent function naming
```
error[E03003]: unbound module member
    PodiumOutpost::update_metadata_uri(user1, outpost, new_uri);
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Invalid module access
```

**Issue**: Function names in tests don't match implementation (update_* vs set_*)

**Solution**: 
1. Use consistent naming across modules:
```move
// In contract
public entry fun set_metadata_uri(...)

// In tests
PodiumOutpost::set_metadata_uri(...)
```

2. Follow naming conventions:
- Use `set_*` for state-changing operations
- Use `get_*` for read-only operations
- Use `update_*` for complex state changes

## Error Category 2: Missing Module Imports
### Error: Unbound standard modules
```
error[E03002]: unbound module
    assert!(vector::length(&events) == 1, 5001);
            ^^^^^^ Unbound module or type alias 'vector'
```

**Solution**: Add all required standard library imports:
```move
use std::vector;
use std::string::{Self, String};
use aptos_framework::object;
use aptos_framework::event;
```

## Error Category 3: Unused Import Warnings
### Warning: Unused module aliases
```
warning[W09001]: unused alias
   use aptos_framework::object::{Self, Object};
                                      ^^^^^^ Unused 'use' of alias 'Object'
```

**Solution**: 
1. Only import what you use:
```move
// Before
use aptos_framework::object::{Self, Object};

// After (if Object isn't used)
use aptos_framework::object;
```

2. Or use explicit type annotations:
```move
let outpost_obj: Object<OutpostData> = object::address_to_object(...);
```

## Best Practices Updates:
1. **Naming Conventions**:
   - Use consistent function names across modules
   - Follow `set_*/get_*/update_*` pattern
   - Document name changes in comments

2. **Import Management**:
   - Only import what's needed
   - Use explicit type annotations
   - Group imports by source (std, aptos_framework, etc.)

3. **Testing Best Practices**:
   - Keep test function names aligned with implementation
   - Add debug prints for state verification
   - Document test scenarios clearly

4. **Error Handling**:
   - Use descriptive error constants
   - Add proper error messages
   - Include debug information in errors