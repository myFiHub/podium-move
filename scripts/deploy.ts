import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { isContractDeployed, CHEERORBOO_ADDRESS } from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load config function
function loadConfig() {
    try {
        const configFile = fs.readFileSync(path.join(__dirname, '../.movement/config.yaml'), 'utf8');
        const config = yaml.parse(configFile);
        
        // Validate private key format
        const privateKey = config.profiles.deployer.private_key;
        if (!privateKey.match(/^0x[0-9a-fA-F]{64}$/)) {
            throw new Error('Invalid private key format. Must be 0x-prefixed 32-byte hex string');
        }
        
        return config.profiles.deployer;
    } catch (error: any) {
        console.error('Error loading config:', error?.message || error);
        process.exit(1);
    }
}

async function main() {
    // Get command line arguments
    const args = process.argv.slice(2);
    const deployTarget = args[0];
    // Fix dry-run detection - it was being ignored
    const isDryRun = args.includes('--dry-run') || args[2] === '--dry-run';

    if (!deployTarget) {
        console.error("Please specify deployment target: 'cheerorboo', 'podium', or 'all'");
        process.exit(1);
    }

    console.log(`Mode: ${isDryRun ? 'Dry Run' : 'Live'}`);

    // Load configuration and setup client
    const config = loadConfig();
    const aptosConfig = new AptosConfig({ 
        network: Network.CUSTOM,
        fullnode: config.rest_url,
        faucet: config.faucet_url,
    });
    
    const aptos = new Aptos(aptosConfig);
    const privateKey = new Ed25519PrivateKey(config.private_key);
    const account = Account.fromPrivateKey({ privateKey });

    console.log(`Deploying from address: ${account.accountAddress}`);

    try {
        switch(deployTarget.toLowerCase()) {
            case 'cheerorboo':
                console.log("\nSimulating CheerOrBooV2 deployment...");
                await deployIfNeeded(aptos, account, "CheerOrBooV2.move", isDryRun);
                break;

            case 'podium':
                console.log("\nDeploying Podium System...");
                await deployPodiumSystem(aptos, account, isDryRun);
                break;

            case 'all':
                console.log("\nChecking CheerOrBooV2 deployment...");
                await deployIfNeeded(aptos, account, "CheerOrBooV2.move", isDryRun);
                
                console.log("\nDeploying Podium System...");
                await deployPodiumSystem(aptos, account, isDryRun);
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

async function deployModule(aptos: Aptos, account: Account, moduleName: string, isDryRun = false) {
    console.log(`${isDryRun ? '[DRY RUN] Would deploy' : 'Deploying'} ${moduleName}...`);
    
    const moduleHex = fs.readFileSync(
        path.join(__dirname, "../sources/", moduleName),
        "utf8"
    );

    if (isDryRun) {
        console.log(`Would deploy module ${moduleName} from address: ${account.accountAddress}`);
        console.log(`Module content length: ${moduleHex.length} bytes`);
        return;
    }

    const transaction = await aptos.publishPackageTransaction({
        account: account.accountAddress,
        metadataBytes: new Uint8Array(),
        moduleBytecode: [Buffer.from(moduleHex).toString("hex")],
    });

    const committedTxn = await aptos.signAndSubmitTransaction({ signer: account, transaction });
    console.log(`Submitted transaction for ${moduleName}: ${committedTxn.hash}`);
    
    const response = await aptos.waitForTransaction({ 
        transactionHash: committedTxn.hash 
    });
    
    console.log(`${moduleName} deployed successfully!`);
    return response;
}

async function deployPodiumSystem(aptos: Aptos, account: Account, isDryRun = false) {
    // Deploy in correct order
    const modules = [
        "PodiumOutpost.move",
        "PodiumPassCoin.move",
        "PodiumPass.move"
    ];

    for (const module of modules) {
        await deployModule(aptos, account, module, isDryRun);
    }

    // Initialize the system
    await initializePodiumSystem(aptos, account, isDryRun);
}

async function initializePodiumSystem(aptos: Aptos, account: Account, isDryRun = false) {
    console.log(`\n${isDryRun ? '[DRY RUN] Would initialize' : 'Initializing'} Podium System...`);

    const initTxns = [
        // Initialize PodiumOutpost first
        {
            function: `${account.accountAddress.toString()}::PodiumOutpost::init_collection`,
            arguments: [],
            typeArguments: []
        },
        {
            function: `${account.accountAddress.toString()}::PodiumOutpost::update_outpost_price`,
            arguments: ["1000"],
            typeArguments: []
        },
        // Initialize PodiumPassCoin properly
        {
            function: `${account.accountAddress.toString()}::PodiumPassCoin::init_module`,
            arguments: [],
            typeArguments: []
        },
        // Initialize PodiumPass with proper parameters
        {
            function: `${account.accountAddress.toString()}::PodiumPass::initialize`,
            arguments: [
                account.accountAddress, // treasury
                4,  // protocol fee percent
                8,  // subject fee percent
                2   // referral fee percent
            ],
            typeArguments: []
        }
    ];

    for (const txn of initTxns) {
        if (isDryRun) {
            console.log(`Would execute: ${txn.function}`);
            console.log(`With arguments:`, txn.arguments);
            continue;
        }
        console.log(`Executing ${txn.function}...`);
        
        const transaction = await aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: {
                function: txn.function as `${string}::${string}::${string}`,
                functionArguments: txn.arguments,
                typeArguments: txn.typeArguments,
            }
        });

        const signature = await aptos.transaction.sign({ 
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

async function deployIfNeeded(aptos: Aptos, account: Account, moduleName: string, isDryRun = false) {
    const isDeployed = await isContractDeployed(aptos, CHEERORBOO_ADDRESS);
    
    if (isDeployed) {
        console.log(`Contract already deployed at ${CHEERORBOO_ADDRESS}`);
        return true;
    }

    console.log(`Deploying contract to ${account.accountAddress}...`);
    return await deployModule(aptos, account, moduleName, isDryRun);
}

// Run deployment
main().catch(console.error);