import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { isContractDeployed, CHEERORBOO_ADDRESS } from './utils.js';

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

    // Test scenarios
    await testCheer(aptos, account);
    await testBoo(aptos, account);
    await testWithParticipants(aptos, account);
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

testCheerScenarios().catch(console.error); 