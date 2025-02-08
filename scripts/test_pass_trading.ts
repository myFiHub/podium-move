import { Aptos, Account, AccountAddress } from "@aptos-labs/ts-sdk";

const MODULE_ADDR = "0x731721a2d14a94504d484f5fb4968e7dc0012edcb89f4f949cd07b82b722af47";
const PODIUM_MODULE = `${MODULE_ADDR}::PodiumProtocol`;

async function main() {
    const client = new Aptos();
    
    // Create test accounts
    const user1 = Account.generate();
    const user2 = Account.generate();
    const target = Account.generate();
    
    console.log("\nAccount Addresses:");
    console.log("User1:", user1.accountAddress.toString());
    console.log("User2:", user2.accountAddress.toString());
    console.log("Target:", target.accountAddress.toString());

    // Fund accounts
    await fundAccount(client, user1.accountAddress.toString(), 100_000_000);
    await fundAccount(client, user2.accountAddress.toString(), 100_000_000);
    await fundAccount(client, target.accountAddress.toString(), 100_000_000);

    console.log("\n=== Testing Pass Trading ===");

    // Test 1: User1 buys passes from Target
    console.log("\nTest 1: User1 buying passes from Target");
    for (let i = 1; i <= 3; i++) {
        const price = await buyPass(client, user1, target.accountAddress.toString(), 1);
        console.log(`User1 bought pass #${i} for ${price} MOVE`);
    }

    // Test 2: User2 buys passes from Target
    console.log("\nTest 2: User2 buying passes from Target");
    for (let i = 1; i <= 2; i++) {
        const price = await buyPass(client, user2, target.accountAddress.toString(), 1);
        console.log(`User2 bought pass #${i} for ${price} MOVE`);
    }

    // Test 3: User1 sells a pass
    console.log("\nTest 3: User1 selling a pass");
    const sellPrice = await sellPass(client, user1, target.accountAddress.toString(), 1);
    console.log(`User1 sold pass for ${sellPrice} MOVE`);

    // Test 4: User1 as target - creating their own passes
    console.log("\nTest 4: User1 as target");
    // First buy from User1's passes
    const user1Price = await buyPass(client, user2, user1.accountAddress.toString(), 1);
    console.log(`User2 bought User1's pass for ${user1Price} MOVE`);

    // Test 5: Multiple targets operating simultaneously
    console.log("\nTest 5: Multiple targets simultaneously");
    const targetPrice = await buyPass(client, user2, target.accountAddress.toString(), 1);
    console.log(`User2 bought Target's pass for ${targetPrice} MOVE`);
    const user1Price2 = await buyPass(client, user2, user1.accountAddress.toString(), 1);
    console.log(`User2 bought User1's pass for ${user1Price2} MOVE`);

    // Print final stats
    console.log("\n=== Final Stats ===");
    await printPassStats(client, target.accountAddress.toString(), "Target");
    await printPassStats(client, user1.accountAddress.toString(), "User1");
}

async function fundAccount(client: Aptos, address: string, amount: number = 100_000_000) {
    // Implementation depends on your testnet/devnet setup
    // You might need to use faucet or transfer from a funded account
}

async function buyPass(
    client: Aptos,
    buyer: Account,
    target: string,
    amount: number
): Promise<number> {
    const price = await getPassPrice(client, target, amount);
    
    const payload = {
        function: `${PODIUM_MODULE}::buy_pass`,
        typeArguments: [],
        functionArguments: [target, amount]
    };

    const txnHash = await submitTransaction(client, buyer, payload);
    await client.waitForTransaction({ transactionHash: txnHash });
    return price;
}

async function sellPass(
    client: Aptos,
    seller: Account,
    target: string,
    amount: number
): Promise<number> {
    const price = await getSellPrice(client, target, amount);
    
    const payload = {
        function: `${PODIUM_MODULE}::sell_pass`,
        typeArguments: [],
        functionArguments: [target, amount]
    };

    const txnHash = await submitTransaction(client, seller, payload);
    await client.waitForTransaction({ transactionHash: txnHash });
    return price;
}

async function getPassPrice(client: Aptos, target: string, amount: number): Promise<number> {
    const response = await client.view({
        payload: {
            function: `${MODULE_ADDR}::PodiumProtocol::calculate_buy_price`,
            typeArguments: [],
            functionArguments: [target, amount]
        }
    });
    return Number(response[0]) / 1e8;
}

async function getSellPrice(client: Aptos, target: string, amount: number): Promise<number> {
    const response = await client.view({
        payload: {
            function: `${MODULE_ADDR}::PodiumProtocol::calculate_sell_price`,
            typeArguments: [],
            functionArguments: [target, amount]
        }
    });
    return Number(response[0]) / 1e8;
}

async function printPassStats(client: Aptos, target: string, label: string) {
    const supply = await client.view({
        payload: {
            function: `${MODULE_ADDR}::PodiumProtocol::get_total_supply`,
            typeArguments: [],
            functionArguments: [target]
        }
    });
    
    const price = await getPassPrice(client, target, 1);
    
    console.log(`${label} Stats:`);
    console.log(`- Total Supply: ${supply[0]}`);
    console.log(`- Current Price: ${price} MOVE`);
}

async function submitTransaction(
    client: Aptos,
    account: Account,
    payload: any
): Promise<string> {
    const rawTxn = await client.transaction.build.simple({
        sender: account.accountAddress,
        data: {
            function: payload.function,
            typeArguments: payload.type_arguments,
            functionArguments: payload.arguments
        }
    });

    const senderAuthenticator = await client.transaction.sign({
        signer: account,
        transaction: rawTxn
    });

    const pendingTx = await client.transaction.submit.simple({
        transaction: rawTxn,
        senderAuthenticator
    });

    await client.waitForTransaction({
        transactionHash: pendingTx.hash
    });

    return pendingTx.hash;
}

main().catch(console.error); 