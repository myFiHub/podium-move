import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";

// Load config function
function loadConfig() {
    const configFile = fs.readFileSync(path.join(__dirname, '../config.yaml'), 'utf8');
    return yaml.parse(configFile);
}

async function main() {
    // Get command line arguments
    const args = process.argv.slice(2);
    const deployTarget = args[0] || 'all'; // Default to 'all' if no argument provided

    // Load configuration and setup client
    const config = loadConfig();
    const aptosConfig = new AptosConfig({ 
        network: Network.CUSTOM,
        fullnode: config.account.rest_url,
        faucet: config.account.faucet_url,
    });
    
    const aptos = new Aptos(aptosConfig);
    const privateKey = new Ed25519PrivateKey(config.private_key);
    const account = Account.fromPrivateKey({ privateKey });

    console.log(`Deploying from address: ${account.accountAddress}`);

    try {
        switch(deployTarget.toLowerCase()) {
            case 'cheerorboo':
                console.log("\nDeploying CheerOrBooV2...");
                await deployModule(aptos, account, "CheerOrBooV2.move");
                break;

            case 'podium':
                console.log("\nDeploying Podium System...");
                await deployPodiumSystem(aptos, account);
                break;

            case 'all':
                console.log("\nDeploying CheerOrBooV2...");
                await deployModule(aptos, account, "CheerOrBooV2.move");
                
                console.log("\nDeploying Podium System...");
                await deployPodiumSystem(aptos, account);
                break;

            default:
                console.error("Invalid deployment target. Use: 'cheerorboo', 'podium', or 'all'");
                process.exit(1);
        }

        console.log("\nDeployment completed successfully!");
    } catch (error) {
        console.error("Deployment failed:", error);
        process.exit(1);
    }
}

async function deployModule(aptos: Aptos, account: Account, moduleName: string) {
    const moduleHex = fs.readFileSync(
        path.join(__dirname, "../sources/", moduleName),
        "utf8"
    );

    const transaction = await aptos.publishPackageTransaction({
        account: account.accountAddress,
        metadataBytes: new Uint8Array(),
        moduleBytecode: [Buffer.from(moduleHex).toString("hex")],
    });

    const committedTxn = await aptos.signAndSubmitTransaction({ signer: account, transaction });

    console.log(`Submitted transaction for ${moduleName}: ${committedTxn.hash}`);
    
    // Wait for transaction completion
    const response = await aptos.waitForTransaction({ 
        transactionHash: committedTxn.hash 
    });
    
    console.log(`${moduleName} deployed successfully!`);
    return response;
}

async function deployPodiumSystem(aptos: Aptos, account: Account) {
    const modules = [
        "PodiumPassCoin.move",
        "PodiumPass.move",
        "PodiumOutpost.move"
    ];

    for (const module of modules) {
        console.log(`Deploying ${module}...`);
        await deployModule(aptos, account, module);
    }

    // Initialize the system
    await initializeSystem(aptos, account);
}

async function initializeSystem(aptos: Aptos, account: Account) {
    const initTxns = [
        {
            function: `${account.accountAddress.toString()}::PodiumPassCoin::initialize`,
            arguments: []
        },
        {
            function: `${account.accountAddress.toString()}::PodiumPass::initialize`,
            arguments: [
                account.accountAddress,
                4,
                8,
                2
            ]
        },
        {
            function: `${account.accountAddress.toString()}::PodiumOutpost::initialize`,
            arguments: [1000000]
        }
    ];

    for (const txn of initTxns) {
        const transaction = await aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: {
                function: txn.function as `${string}::${string}::${string}`,
                functionArguments: txn.arguments,
                typeArguments: [],
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

        console.log(`Submitted initialization transaction: ${committedTxn.hash}`);
        await aptos.waitForTransaction({ 
            transactionHash: committedTxn.hash 
        });
        console.log(`Initialized ${txn.function}`);
    }
}

async function verifyDeployment(aptos: Aptos, account: Account, moduleName: string) {
    try {
        const resources = await aptos.getAccountResources({ 
            accountAddress: account.accountAddress 
        });
        return resources.some(r => r.type.includes(moduleName));
    } catch {
        return false;
    }
}

// Run deployment
main().catch(console.error);