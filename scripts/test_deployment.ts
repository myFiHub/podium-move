import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { isContractDeployed, CHEERORBOO_ADDRESS, FIHUB_ADDRESS } from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function loadConfig() {
    const configFile = fs.readFileSync(path.join(__dirname, '../.movement/config.yaml'), 'utf8');
    const config = yaml.parse(configFile);
    return config.profiles.deployer;
}

async function testCheerScenarios() {
    const config = loadConfig();
    const aptos = new Aptos(new AptosConfig({ 
        network: Network.CUSTOM,
        fullnode: config.rest_url,
        faucet: config.faucet_url,
    }));

    // Verify deployment
    const isDeployed = await isContractDeployed(aptos, CHEERORBOO_ADDRESS);
    if (!isDeployed) {
        console.error(`Contract not found at ${CHEERORBOO_ADDRESS}`);
        process.exit(1);
    }
    console.log(`Contract verified at ${CHEERORBOO_ADDRESS}`);

    const privateKey = new Ed25519PrivateKey(config.private_key);
    const account = Account.fromPrivateKey({ privateKey });

    // Basic Tests
    await testBasicCheer(aptos, account);
    await testBasicBoo(aptos, account);
    
    // Advanced Tests
    await testMultipleParticipants(aptos, account);
    await testZeroParticipants(aptos, account);
    await testMaxAllocation(aptos, account);
    await testMinAllocation(aptos, account);
    await testFeeDistribution(aptos, account);
}

// Helper function to pad addresses
function padAddress(addr: string): string {
    return addr.replace('0x', '').padStart(64, '0');
}

async function testCheer(aptos: Aptos, account: Account) {
    console.log("\nTesting Cheer...");
    await executeTransaction(aptos, account, {
        target: `0x${padAddress("123")}`,
        participants: [],
        isCheer: true,
        amount: 100,
        targetAllocation: 50,
        identifier: [1,2,3]
    });
}

async function testBoo(aptos: Aptos, account: Account) {
    console.log("\nTesting Boo...");
    await executeTransaction(aptos, account, {
        target: `0x${padAddress("456")}`,
        participants: [],
        isCheer: false,
        amount: 200,
        targetAllocation: 30,
        identifier: [4,5,6]
    });
}

async function testWithParticipants(aptos: Aptos, account: Account) {
    console.log("\nTesting with participants...");
    await executeTransaction(aptos, account, {
        target: `0x${padAddress("789")}`,
        participants: [`0x${padAddress("abc")}`, `0x${padAddress("def")}`],
        isCheer: true,
        amount: 300,
        targetAllocation: 40,
        identifier: [7,8,9]
    });
}

async function executeTransaction(aptos: Aptos, account: Account, params: any) {
    try {
        const transaction = await aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: {
                function: `${CHEERORBOO_ADDRESS}::CheerOrBooV2::cheer_or_boo`,
                typeArguments: [],
                functionArguments: [
                    params.target,
                    params.participants,
                    params.isCheer,
                    params.amount,
                    params.targetAllocation,
                    params.identifier
                ]
            }
        });

        const signature = aptos.transaction.sign({ 
            signer: account, 
            transaction 
        });

        const committedTxn = await aptos.transaction.submit.simple({
            transaction,
            senderAuthenticator: signature,
        });

        console.log("Transaction submitted:", committedTxn.hash);
        
        await aptos.waitForTransaction({ 
            transactionHash: committedTxn.hash 
        });
        
        console.log("Transaction completed successfully!");
    } catch (error) {
        console.error("Transaction failed:", error);
    }
}

// Test Basic Cheer with Fee Verification
async function testBasicCheer(aptos: Aptos, account: Account) {
    console.log("\nTesting Basic Cheer with Fee Verification...");
    const amount = 1000;
    const targetAllocation = 50;
    const fee = amount * 5 / 100; // 5% fee
    const netAmount = amount - fee;
    const targetAmount = netAmount * targetAllocation / 100;

    const target = `0x${padAddress("123")}`;
    
    // Get initial balances
    const initialTargetBalance = await getBalance(aptos, target);
    const initialFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);

    await executeTransaction(aptos, account, {
        target,
        participants: [],
        isCheer: true,
        amount,
        targetAllocation,
        identifier: [1,2,3]
    });

    // Verify balances
    const finalTargetBalance = await getBalance(aptos, target);
    const finalFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);

    console.log(`Target received: ${finalTargetBalance - initialTargetBalance} (expected: ${targetAmount})`);
    console.log(`Fee collected: ${finalFeeBalance - initialFeeBalance} (expected: ${fee})`);
}

// Test Multiple Participants with Equal Distribution
async function testMultipleParticipants(aptos: Aptos, account: Account) {
    console.log("\nTesting Multiple Participants Distribution...");
    const amount = 1000;
    const targetAllocation = 40;
    const participants = [
        `0x${padAddress("abc")}`,
        `0x${padAddress("def")}`,
        `0x${padAddress("ghi")}`
    ];

    const fee = amount * 5 / 100;
    const netAmount = amount - fee;
    const targetAmount = netAmount * targetAllocation / 100;
    const participantAmount = (netAmount - targetAmount) / participants.length;

    // Get initial balances
    const initialBalances = await Promise.all(
        participants.map(p => getBalance(aptos, p))
    );

    await executeTransaction(aptos, account, {
        target: `0x${padAddress("789")}`,
        participants,
        isCheer: true,
        amount,
        targetAllocation,
        identifier: [7,8,9]
    });

    // Verify participant distributions
    const finalBalances = await Promise.all(
        participants.map(p => getBalance(aptos, p))
    );

    participants.forEach((p, i) => {
        console.log(`Participant ${i} received: ${finalBalances[i] - initialBalances[i]} (expected: ${participantAmount})`);
    });
}

// Test Edge Cases
async function testZeroParticipants(aptos: Aptos, account: Account) {
    console.log("\nTesting Zero Participants (100% to target)...");
    const target = `0x${padAddress("321")}`;
    const amount = 1000;
    const targetAllocation = 100;

    const initialBalance = await getBalance(aptos, target);

    await executeTransaction(aptos, account, {
        target,
        participants: [],
        isCheer: true,
        amount,
        targetAllocation,
        identifier: [10,11,12]
    });

    const finalBalance = await getBalance(aptos, target);
    console.log(`Target received: ${finalBalance - initialBalance}`);
}

// Test Maximum Allocation
async function testMaxAllocation(aptos: Aptos, account: Account) {
    console.log("\nTesting Maximum Allocation...");
    await executeTransaction(aptos, account, {
        target: `0x${padAddress("999")}`,
        participants: [],
        isCheer: true,
        amount: 1000,
        targetAllocation: 100, // Maximum possible
        identifier: [13,14,15]
    });
}

// Test Minimum Allocation
async function testMinAllocation(aptos: Aptos, account: Account) {
    console.log("\nTesting Minimum Allocation...");
    const target = `0x${padAddress("888")}`;
    const participants = [`0x${padAddress("777")}`];

    await executeTransaction(aptos, account, {
        target,
        participants,
        isCheer: true,
        amount: 1000,
        targetAllocation: 0, // Minimum possible
        identifier: [16,17,18]
    });
}

// Test Fee Distribution
async function testFeeDistribution(aptos: Aptos, account: Account) {
    console.log("\nTesting Fee Distribution...");
    const amount = 10000; // Larger amount for clearer fee calculation
    const fee = amount * 5 / 100;

    const initialFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);

    await executeTransaction(aptos, account, {
        target: `0x${padAddress("555")}`,
        participants: [],
        isCheer: true,
        amount,
        targetAllocation: 50,
        identifier: [19,20,21]
    });

    const finalFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);
    console.log(`Fee collected: ${finalFeeBalance - initialFeeBalance} (expected: ${fee})`);
}

interface CoinStore {
    data: {
        coin: {
            value: string;
        };
    };
}

async function getBalance(aptos: Aptos, address: string): Promise<number> {
    try {
        const resources = await aptos.getAccountResources({
            accountAddress: address
        });
        const aptosCoin = resources.find(r => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>") as unknown as CoinStore;
        return aptosCoin?.data?.coin?.value ? Number(aptosCoin.data.coin.value) : 0;
    } catch {
        return 0;
    }
}

async function testBasicBoo(aptos: Aptos, account: Account) {
    console.log("\nTesting Basic Boo with Fee Verification...");
    const amount = 1000;
    const targetAllocation = 30;
    const fee = amount * 5 / 100; // 5% fee
    const netAmount = amount - fee;
    const targetAmount = netAmount * targetAllocation / 100;

    const target = `0x${padAddress("456")}`;
    
    // Get initial balances
    const initialTargetBalance = await getBalance(aptos, target);
    const initialFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);

    await executeTransaction(aptos, account, {
        target,
        participants: [],
        isCheer: false, // This is a boo
        amount,
        targetAllocation,
        identifier: [4,5,6]
    });

    // Verify balances
    const finalTargetBalance = await getBalance(aptos, target);
    const finalFeeBalance = await getBalance(aptos, FIHUB_ADDRESS);

    console.log(`Target received: ${finalTargetBalance - initialTargetBalance} (expected: ${targetAmount})`);
    console.log(`Fee collected: ${finalFeeBalance - initialFeeBalance} (expected: ${fee})`);
}

testCheerScenarios().catch(console.error); 