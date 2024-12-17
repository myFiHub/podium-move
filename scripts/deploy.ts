import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { isContractDeployed, CHEERORBOO_ADDRESS, getDeployerAddresses, formatAddress } from './utils.js';
import { viewFunction } from './utils.js';
import {
    verifyDecimals,
    verifyOutpostCollection,
    verifyPermissions,
    validateSystemState,
    validateAddresses,
    toMoveAmount
} from './utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type DeployTarget = 'cheerorboo' | 'podium' | 'all';

interface DeploymentOptions {
    target: DeployTarget;
    isDryRun: boolean;
    isDebug: boolean;
}

function parseArgs(): DeploymentOptions {
    const args = process.argv.slice(2);
    const target = args[0] as DeployTarget || '';
    
    return {
        target,
        isDryRun: args.includes('--dry-run'),
        isDebug: args.includes('--debug')
    };
}

async function loadConfig() {
    try {
        const configPath = path.join(__dirname, '../.movement/config.yaml');
        
        if (!fs.existsSync(configPath)) {
            throw new Error(`Config file not found at ${configPath}`);
        }
        
        const configFile = await fs.promises.readFile(configPath, 'utf8');
        const config = yaml.parse(configFile);
        
        if (!config?.profiles?.deployer?.private_key) {
            throw new Error('Invalid config structure - missing deployer profile or private key');
        }
        
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

const addresses = getDeployerAddresses();
const MODULE_ADDRESSES = {
    PODIUM: formatAddress(addresses.deployerAddress),
    PODIUM_PASS: 'PodiumPass',
    PODIUM_PASS_COIN: 'PodiumPassCoin'
};

async function checkModuleInitialized(aptos: Aptos, account: Account, moduleName: string): Promise<boolean> {
    try {
        const result = await viewFunction(aptos, {
            function: `${MODULE_ADDRESSES.PODIUM}::${moduleName}::is_initialized`,
            type_arguments: [],
            arguments: []
        });
        return result[0] as boolean;
    } catch (error) {
        console.log(`Module ${moduleName} not initialized or not found`);
        return false;
    }
}

const main = async () => {
    const options = parseArgs();
    try {
        if (!options.target) {
            throw new Error("Please specify deployment target: 'cheerorboo', 'podium', or 'all'");
        }

        console.log(`=== Deployment Configuration ===`);
        console.log(`Target: ${options.target}`);
        console.log(`Mode: ${options.isDryRun ? 'Dry Run' : 'Live'}`);
        console.log(`Debug: ${options.isDebug ? 'Enabled' : 'Disabled'}`);

        const config = await loadConfig();
        const aptosConfig = new AptosConfig({ 
            network: Network.CUSTOM,
            fullnode: config.rest_url,
            faucet: config.faucet_url,
        });
        
        const aptos = new Aptos(aptosConfig);
        const privateKey = new Ed25519PrivateKey(config.private_key);
        const account = Account.fromPrivateKey({ privateKey });

        if (options.isDebug) {
            console.log(`\n=== Debug Information ===`);
            console.log(`Network: ${aptosConfig.network}`);
            console.log(`Fullnode URL: ${aptosConfig.fullnode}`);
            console.log(`Account Address: ${account.accountAddress}`);
        }

        const passCoinInitialized = await checkModuleInitialized(aptos, account, MODULE_ADDRESSES.PODIUM_PASS_COIN);
        const passInitialized = await checkModuleInitialized(aptos, account, MODULE_ADDRESSES.PODIUM_PASS);

        console.log(`\n=== Module Status ===`);
        console.log(`PodiumPassCoin initialized: ${passCoinInitialized}`);
        console.log(`PodiumPass initialized: ${passInitialized}`);

        if (!passCoinInitialized) {
            console.log("\nInitializing PodiumPassCoin module...");
            if (!options.isDryRun) {
                await deployModule(aptos, account, "PodiumPassCoin.move", false);
            } else {
                console.log("[DRY RUN] Would deploy PodiumPassCoin");
            }
        }

        if (!passInitialized) {
            console.log("\nInitializing PodiumPass module...");
            if (!options.isDryRun) {
                await deployModule(aptos, account, "PodiumPass.move", false);
            } else {
                console.log("[DRY RUN] Would deploy PodiumPass");
            }
        }

        console.log("Checking PodiumOutpost collection...");
        const outpostInit = {
            function: `${account.accountAddress.toString()}::PodiumOutpost::init_collection`,
            arguments: [],
            typeArguments: []
        };
        
        if (options.isDryRun) {
            console.log(`Would execute: ${outpostInit.function}`);
        } else {
            await executeTransaction(aptos, account, outpostInit);
        }

        switch(options.target.toLowerCase()) {
            case 'cheerorboo':
                await deployIfNeeded(aptos, account, "CheerOrBooV2.move", options.isDryRun);
                break;
            case 'podium':
                await deployPodiumSystem(aptos, account, options.isDryRun);
                break;
            case 'all':
                await deployIfNeeded(aptos, account, "CheerOrBooV2.move", options.isDryRun);
                await deployPodiumSystem(aptos, account, options.isDryRun);
                break;
            default:
                throw new Error("Invalid deployment target. Use: 'cheerorboo', 'podium', or 'all'");
        }

        console.log("\nDeployment completed successfully!");
    } catch (error: any) {
        console.error("\n=== Deployment Failed ===");
        if (options.isDebug) {
            console.error("Error details:", error);
        } else {
            console.error("Error:", error.message);
            console.error("Run with --debug flag for more details");
        }
        process.exit(1);
    }
};

function shouldDeployFile(file: string): boolean {
    return !file.endsWith('_test.move');
}

async function deployModule(aptos: Aptos, account: Account, moduleName: string, isDryRun = false) {
    if (moduleName.endsWith('_test.move')) {
        console.log(`Skipping test file: ${moduleName}`);
        return;
    }

    console.log(`\n=== Deployment Details ===`);
    console.log(`Module: ${moduleName}`);
    console.log(`Deployer Address: ${account.accountAddress}`);
    console.log(`Mode: ${isDryRun ? 'Dry Run' : 'Live'}`);
    
    try {
        const moduleHex = fs.readFileSync(
            path.join(__dirname, "../sources/", moduleName),
            "utf8"
        );

        console.log(`Module file size: ${moduleHex.length} bytes`);

        if (isDryRun) {
            console.log(`[DRY RUN] Would deploy module ${moduleName}`);
            return;
        }

        const resources = await aptos.account.getAccountResources({
            accountAddress: account.accountAddress,
        });
        console.log(`Account has ${resources.length} resources`);

        if (moduleName === "PodiumPass.move") {
            const passCoinInit = await verifyModuleInitialized(aptos, account, "PodiumPassCoin");
            if (!passCoinInit) {
                throw new Error("PodiumPassCoin must be initialized before PodiumPass");
            }
        }

        const transaction = await aptos.publishPackageTransaction({
            account: account.accountAddress,
            metadataBytes: new Uint8Array(),
            moduleBytecode: [Buffer.from(moduleHex).toString("hex")],
        });

        console.log(`\nTransaction payload created successfully`);
        console.log(`Attempting to submit transaction...`);

        const committedTxn = await aptos.signAndSubmitTransaction({ signer: account, transaction });
        console.log(`Transaction submitted. Hash: ${committedTxn.hash}`);
        
        const response = await aptos.waitForTransaction({ 
            transactionHash: committedTxn.hash,
            options: {
                timeoutSecs: 30,
                checkSuccess: true
            }
        });
        
        console.log(`\nTransaction Details:`);
        console.log(`Status: ${response.success ? 'Success' : 'Failed'}`);
        console.log(`Gas used: ${response.gas_used}`);
        
        if (!response.success) {
            throw new Error(`Transaction failed: ${response.vm_status}`);
        }

        if (!isDryRun) {
            // Verify module-specific initialization
            switch(moduleName) {
                case "PodiumOutpost.move":
                    const collectionValid = await verifyOutpostCollection(aptos, account);
                    if (!collectionValid) {
                        throw new Error("Outpost collection initialization failed");
                    }
                    break;
                
                case "PodiumPassCoin.move":
                    const decimalsValid = await verifyDecimals(aptos, account);
                    if (!decimalsValid) {
                        throw new Error("PodiumPassCoin decimal configuration failed");
                    }
                    break;
                
                case "PodiumPass.move":
                    const permissionsValid = await verifyPermissions(aptos, account);
                    if (!permissionsValid) {
                        throw new Error("PodiumPass permissions initialization failed");
                    }
                    break;
            }
        }

        console.log(`${moduleName} deployed and validated successfully!`);
        return response;
    } catch (error: any) {
        console.error(`\n=== Module Deployment Error ===`);
        console.error(`Failed to deploy ${moduleName}`);
        if (error.transaction?.vm_status) {
            console.error(`VM Status: ${error.transaction.vm_status}`);
            if (error.transaction.vm_status.includes("ABORTED")) {
                console.error("Contract initialization failed - check permissions and prerequisites");
            }
        }
        throw error;
    }
}

async function verifyModuleInitialized(aptos: Aptos, account: Account, moduleName: string): Promise<boolean> {
    try {
        const response = await aptos.view({
            payload: {
                function: `${account.accountAddress}::${moduleName}::is_initialized` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });
        return response[0] as boolean;
    } catch (error) {
        console.error(`Failed to verify ${moduleName} initialization:`, error);
        return false;
    }
}

async function deployPodiumSystem(aptos: Aptos, account: Account, isDryRun = false) {
    console.log("\n=== Deploying Podium System ===");

    // Pre-deployment validation
    console.log("\n--- Pre-deployment Validation ---");
    const addressValidation = validateAddresses(account);
    if (!addressValidation.success) {
        console.error("Address validation failed for:", addressValidation.mismatches);
        throw new Error("Address validation failed - check Move.toml configuration");
    }
    console.log("✓ Address validation successful");

    // First Phase: Deploy base modules
    console.log("\n--- Phase 1: Deploying Base Modules ---");
    
    // Deploy modules in correct order
    const modules = [
        "PodiumPassCoin.move",
        "PodiumOutpost.move",
        "PodiumPass.move"
    ];

    // Check dependencies and simulate/deploy each module
    for (const module of modules) {
        console.log(`\nProcessing ${module}...`);
        
        // Check if module is already deployed
        const isDeployed = await isModuleDeployed(aptos, account, module);
        if (isDeployed) {
            console.log(`Module ${module} already deployed, skipping...`);
            continue;
        }

        if (isDryRun) {
            // Simulate module deployment
            const moduleHex = fs.readFileSync(
                path.join(__dirname, "../sources/", module),
                "utf8"
            );

            // First build the transaction
            const transaction = await aptos.transaction.build.simple({
                sender: account.accountAddress,
                data: {
                    function: `${account.accountAddress}::${module.split('.')[0]}::init_module` as `${string}::${string}::${string}`,
                    functionArguments: [],
                    typeArguments: []
                }
            });

            // Then simulate the built transaction
            const simulation = await aptos.transaction.simulate.simple({
                signerPublicKey: account.publicKey,
                transaction
            });

            console.log(`Simulation results for ${module}:`);
            console.log(`Success: ${simulation[0]?.success ?? false}`);
            console.log(`Gas estimate: ${simulation[0].gas_used}`);
            
            if (!simulation[0].success) {
                throw new Error(`Deployment simulation failed for ${module}: ${simulation[0].vm_status}`);
            }
        } else {
            await deployModule(aptos, account, module, false);
        }
    }

    // Phase 2: Initialize modules
    console.log("\n--- Phase 2: Module Initialization ---");
    
    const initTxns = [
        {
            function: `${account.accountAddress}::PodiumPassCoin::init_module`,
            arguments: [],
            typeArguments: []
        },
        {
            function: `${account.accountAddress}::PodiumPass::initialize`,
            arguments: [
                account.accountAddress,
                4,
                8,
                2
            ],
            typeArguments: []
        },
        {
            function: `${account.accountAddress}::PodiumOutpost::init_collection`,
            arguments: [],
            typeArguments: []
        },
        {
            function: `${account.accountAddress}::PodiumOutpost::update_outpost_price`,
            arguments: [toMoveAmount(30)],
            typeArguments: []
        }
    ];

    // Execute or simulate initialization transactions
    for (const txn of initTxns) {
        console.log(`\nProcessing ${txn.function}...`);
        const result = await executeTransaction(aptos, account, txn, isDryRun);
        
        if (!result) {
            throw new Error(`Failed to ${isDryRun ? 'simulate' : 'execute'} ${txn.function}`);
        }
    }

    // Phase 3: Validation
    console.log("\n--- Phase 3: System Validation ---");
    
    if (isDryRun) {
        console.log("Simulating system validation...");
        try {
            // Simulate view function calls
            const simulations = await Promise.all([
                simulateViewFunction(aptos, account, "PodiumPassCoin::is_initialized"),
                simulateViewFunction(aptos, account, "PodiumPass::is_initialized"),
                simulateViewFunction(aptos, account, "PodiumOutpost::get_collection_data"),
                simulateViewFunction(aptos, account, "PodiumOutpost::get_outpost_purchase_price")
            ]);

            console.log("Validation simulations successful");
        } catch (error) {
            console.error("Validation simulation failed:", error);
            throw error;
        }
    } else {
        // Real validation
        const systemValidation = await validateSystemState(aptos, account);
        if (!systemValidation.success) {
            throw new Error("System validation failed");
        }
    }

    console.log("\n=== Podium System Deployment Complete ===");
}

// Add helper function for view function simulation
async function simulateViewFunction(aptos: Aptos, account: Account, func: string): Promise<boolean> {
    try {
        const simulation = await aptos.view({
            payload: {
                function: `${account.accountAddress}::${func}` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });
        return true;
    } catch (error) {
        console.error(`View function simulation failed for ${func}:`, error);
        return false;
    }
}

// Add this helper function for full system validation
async function validateFullSystem(aptos: Aptos, account: Account): Promise<boolean> {
    try {
        // Check all modules exist
        const modules = ["PodiumOutpost", "PodiumPassCoin", "PodiumPass"];
        for (const module of modules) {
            const moduleExists = await aptos.getAccountModule({
                accountAddress: account.accountAddress,
                moduleName: module
            }).then(() => true).catch(() => false);
            
            if (!moduleExists) {
                console.error(`Module ${module} not found`);
                return false;
            }
        }

        // Check initialization status
        const passCoinInitialized = await verifyModuleInitialized(aptos, account, "PodiumPassCoin");
        const passInitialized = await verifyModuleInitialized(aptos, account, "PodiumPass");

        if (!passCoinInitialized || !passInitialized) {
            console.error("Module initialization check failed");
            return false;
        }

        return true;
    } catch (error) {
        console.error("System validation error:", error);
        return false;
    }
}

async function deployIfNeeded(aptos: Aptos, account: Account, moduleName: string, isDryRun = false) {
    console.log(`\n=== Checking Deployment Status ===`);
    try {
        const isDeployed = await isContractDeployed(aptos, CHEERORBOO_ADDRESS);
        console.log(`Contract deployment status at ${CHEERORBOO_ADDRESS}: ${isDeployed ? 'Deployed' : 'Not deployed'}`);
        
        if (isDeployed) {
            console.log(`Contract already deployed at ${CHEERORBOO_ADDRESS}`);
            return true;
        }

        console.log(`Initiating deployment to ${account.accountAddress}...`);
        return await deployModule(aptos, account, moduleName, isDryRun);
    } catch (error) {
        console.error(`\n=== Deployment Check Error ===`);
        console.error(`Failed to check or deploy contract`);
        console.error(error);
        throw error;
    }
}

async function simulateTransaction(aptos: Aptos, account: Account, txn: any) {
    try {
        // Build the transaction payload
        const transaction = await aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: {
                function: txn.function as `${string}::${string}::${string}`,
                functionArguments: txn.arguments,
                typeArguments: txn.typeArguments || [],
            }
        });

        // Simulate using the built transaction
        const [simulation] = await aptos.transaction.simulate.simple({
            signerPublicKey: account.publicKey,
            transaction,
        });
        
        console.log(`Simulation results for ${txn.function}:`);
        console.log(`Success: ${simulation?.success ?? false}`);
        console.log(`Gas used: ${simulation.gas_used}`);
        return simulation?.success ?? false;
    } catch (error) {
        console.error(`Simulation failed:`, error);
        return false;
    }
}

async function executeTransaction(aptos: Aptos, account: Account, txn: any, isDryRun = false) {
    if (isDryRun) {
        return await simulateTransaction(aptos, account, txn);
    }
    
    const transaction = await aptos.transaction.build.simple({
        sender: account.accountAddress,
        data: {
            function: txn.function as `${string}::${string}::${string}`,
            functionArguments: txn.arguments,
            typeArguments: txn.typeArguments || [],
        },
    });

    const senderAuthenticator = await aptos.transaction.sign({
        signer: account,
        transaction,
    });

    const committedTxn = await aptos.transaction.submit.simple({
        transaction,
        senderAuthenticator,
    });

    return await aptos.waitForTransaction({
        transactionHash: committedTxn.hash,
    });
}

async function upgradeModule(aptos: Aptos, account: Account, moduleName: string, newCode: string) {
    const transaction = await aptos.transaction.build.simple({
        sender: account.accountAddress,
        data: {
            function: `${account.accountAddress}::${moduleName}::upgrade` as `${string}::${string}::${string}`,
            functionArguments: [
                new Uint8Array(),
                [Buffer.from(newCode).toString("hex")]
            ],
            typeArguments: [],
        },
    });

    const senderAuthenticator = await aptos.transaction.sign({
        signer: account,
        transaction,
    });

    const committedTxn = await aptos.transaction.submit.simple({
        transaction,
        senderAuthenticator,
    });

    return await aptos.waitForTransaction({
        transactionHash: committedTxn.hash,
    });
}

// Add this helper function to check module deployment status
async function isModuleDeployed(aptos: Aptos, account: Account, moduleName: string): Promise<boolean> {
    try {
        const moduleExists = await aptos.getAccountModule({
            accountAddress: account.accountAddress,
            moduleName: moduleName.replace('.move', '')  // Remove .move extension
        });
        return !!moduleExists;
    } catch (error) {
        return false;
    }
}

try {
    await main();
} catch (error) {
    console.error("\n=== Unhandled Error ===");
    console.error("An unexpected error occurred:");
    console.error(error);
    process.exit(1);
}