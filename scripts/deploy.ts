import { Account, Aptos, AptosConfig, Network, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { isContractDeployed, CHEERORBOO_ADDRESS, getDeployerAddresses, formatAddress, isModuleDeployed } from './utils.js';
import { viewFunction } from './utils.js';
import {
    verifyDecimals,
    verifyOutpostCollection,
    verifyPermissions,
    validateSystemState,
    validateAddresses,
    toMoveAmount
} from './utils.js';
import { execSync } from 'child_process';
import { MoveConfigManager } from './move_config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type DeployTarget = 'cheerorboo' | 'podium' | 'all';

interface DeploymentOptions {
    target: DeployTarget;
    isDryRun: boolean;
    isDebug: boolean;
    mode: 'dev' | 'prod';
}

function parseArgs(): DeploymentOptions {
    const args = process.argv.slice(2);
    const target = args[0] as DeployTarget || '';
    
    return {
        target,
        isDryRun: args.includes('--dry-run'),
        isDebug: args.includes('--debug'),
        mode: args.includes('--dev') ? 'dev' : 'prod'
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
    } catch (error: any) {
        if (error?.data?.error_code !== 'module_not_found') {
            console.log(`Module ${moduleName} not initialized or not found:`, error);
        }
        return false;
    }
}

const main = async () => {
    const options = parseArgs();
    const moveConfig = new MoveConfigManager();
    
    try {
        moveConfig.backup();
        
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
                await deployPodiumSystem(aptos, account, options.isDryRun, options);
                break;
            case 'all':
                await deployIfNeeded(aptos, account, "CheerOrBooV2.move", options.isDryRun);
                await deployPodiumSystem(aptos, account, options.isDryRun, options);
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
    } finally {
        try {
            moveConfig.restore();
        } catch (e) {
            console.error('Failed to restore Move.toml:', e);
        }
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

async function deployPodiumSystem(aptos: Aptos, account: Account, isDryRun = false, options: DeploymentOptions) {
    const moveConfig = new MoveConfigManager();
    try {
        moveConfig.backup();

        log('Deploying Podium System...', options);
        
        // Pre-deployment validation
        console.log("\n--- Pre-deployment Validation ---");
        const addressValidation = validateAddresses(account);
        if (!addressValidation.success) {
            throw new Error("Address validation failed - check Move.toml configuration");
        }
        console.log("✓ Address validation successful");

        // First Phase: Deploy base modules
        console.log("\n--- Phase 1: Deploying Base Modules ---");
        
        const modules = [
            "PodiumPassCoin.move",
            "PodiumOutpost.move",
            "PodiumPass.move"
        ];

        // Track simulated deployments for dry run
        const simulatedDeployments = new Set<string>();

        for (const module of modules) {
            console.log(`\nProcessing ${module}...`);
            
            if (isDryRun) {
                try {
                    // First compile the module
                    if (options.isDebug) {
                        console.log('Compiling module...');
                    }
                    
                    try {
                        const MOVE_QUIET = process.env.MOVE_QUIET === '1';

                        // Update compile command
                        const compileCommand = `aptos move compile ${options.mode === 'dev' ? '--dev' : ''} ${MOVE_QUIET ? '--quiet' : ''}`;

                        const output = execSync(compileCommand, {
                            cwd: path.join(__dirname, '..'),
                            stdio: ['ignore', 'pipe', 'pipe'],
                            env: {
                                ...process.env,
                                MOVE_COMPILER_DEBUG: options.isDebug ? '1' : '0'
                            }
                        }).toString();

                        // Only show relevant parts of output
                        const relevantOutput = output
                            .split('\n')
                            .filter(line => (
                                !line.includes('label') && 
                                !line.includes('UPDATING GIT DEPENDENCY') &&
                                !line.startsWith('Compiling') &&
                                !line.match(/^\s*$/) // Skip empty lines
                            ))
                            .join('\n');

                        if (options.isDebug) {
                            console.log(relevantOutput);
                        } else {
                            // Only show compilation status
                            if (relevantOutput.includes('Compilation successful')) {
                                console.log('Compilation successful');
                            }
                        }
                    } catch (error) {
                        handleMoveAbort(error);
                    }

                    // Read the compiled bytecode
                    const buildPath = path.join(__dirname, '../build/PodiumProtocol/bytecode_modules', 
                        module.replace('.move', '.mv'));
                    
                    if (!fs.existsSync(buildPath)) {
                        console.error(`Compiled bytecode not found at ${buildPath}`);
                        if (options.isDebug) {
                            // List contents of build directory
                            try {
                                const buildDir = path.join(__dirname, '../build');
                                console.log('\nBuild directory contents:');
                                const files = fs.readdirSync(buildDir, { recursive: true });
                                console.log(files);
                            } catch (e) {
                                console.error('Could not read build directory');
                            }
                        }
                        continue;
                    }

                    const bytecode = fs.readFileSync(buildPath);

                    if (options.isDebug) {
                        console.log(`Module bytecode size: ${bytecode.length} bytes`);
                        console.log(`Module path: ${buildPath}`);
                    }

                    // Use publishPackageTransaction with compiled bytecode
                    const transaction = await aptos.publishPackageTransaction({
                        account: account.accountAddress,
                        metadataBytes: new Uint8Array(),
                        moduleBytecode: [bytecode.toString('hex')]
                    });

                    if (options.isDebug) {
                        console.log('\nTransaction details:');
                        // Convert BigInt to string in transaction object
                        const txnDetails = JSON.parse(JSON.stringify(transaction, (key, value) => {
                            if (typeof value === 'bigint') {
                                return value.toString();
                            }
                            return value;
                        }));
                        console.log(txnDetails);
                    }

                    // Simulate deployment
                    console.log(`Simulating deployment of ${module}...`);
                    const [simulation] = await aptos.transaction.simulate.simple({
                        transaction,
                        signerPublicKey: account.publicKey,
                        options: {
                            estimateGasUnitPrice: true,
                            estimateMaxGasAmount: true
                        }
                    });

                    console.log(`Simulation results:`);
                    console.log(`Success: ${simulation?.success ?? false}`);
                    console.log(`Gas estimate: ${simulation.gas_used}`);
                    if (simulation.vm_status) {
                        console.log(`VM Status: ${simulation.vm_status}`);
                    }
                    if (options.isDebug && simulation.changes) {
                        console.log('\nSimulated changes:');
                        console.log(JSON.stringify(simulation.changes, null, 2));
                    }

                    if (simulation?.success) {
                        simulatedDeployments.add(module.replace('.move', ''));
                    }
                } catch (error: any) {
                    console.error(`Simulation failed for ${module}:`, error?.message || error);
                    if (error?.data?.vm_status) {
                        console.error(`VM Status: ${error.data.vm_status}`);
                    }
                    if (options.isDebug) {
                        console.error('Full error:', error);
                    }
                }
                continue;
            }

            const isDeployed = await isModuleDeployed(aptos, account, module);
            if (isDeployed) {
                console.log(`Module ${module} already deployed, skipping...`);
                continue;
            }

            await deployModule(aptos, account, module, false);
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

        for (const txn of initTxns) {
            console.log(`\nProcessing ${txn.function}...`);
            
            if (isDryRun) {
                // Extract module name from function
                const moduleName = txn.function.split('::')[2];
                if (!simulatedDeployments.has(moduleName)) {
                    console.log(`Skipping initialization simulation for ${moduleName} - module not deployed`);
                    continue;
                }

                try {
                    // Build the transaction
                    const transaction = await aptos.transaction.build.simple({
                        sender: account.accountAddress,
                        data: {
                            function: txn.function as `${string}::${string}::${string}`,
                            functionArguments: txn.arguments,
                            typeArguments: txn.typeArguments
                        }
                    });

                    // Simulate without authentication check
                    const [simulation] = await aptos.transaction.simulate.simple({
                        transaction
                    });

                    console.log(`Simulation results:`);
                    console.log(`Success: ${simulation?.success ?? false}`);
                    console.log(`Gas estimate: ${simulation.gas_used}`);
                } catch (error: any) {
                    console.error(`Simulation failed:`, error?.message || error);
                }
            } else {
                const result = await executeTransaction(aptos, account, txn, false);
                if (!result) {
                    throw new Error(`Failed to execute ${txn.function}`);
                }
            }
        }

        console.log("\n=== Podium System Deployment Complete ===");

        if (options.isDebug) {
            log('Deployment simulation complete', options, 'debug');
            // Show detailed simulation results only in debug mode
        } else {
            log('Deployment successful', options);
        }

    } catch (error) {
        moveConfig.restore();
        throw error;
    }
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

function log(message: string, options: DeploymentOptions, level: 'info' | 'debug' = 'info') {
    if (level === 'debug' && !options.isDebug) {
        return;
    }
    console.log(message);
}

function handleMoveAbort(error: any) {
    if (error?.message?.includes('Move abort')) {
        const abortCode = error.message.match(/0x1::util: (0x[0-9a-f]+)/);
        if (abortCode) {
            switch (abortCode[1]) {
                case '0x10001':
                    throw new Error('Module initialization failed - check account permissions');
                // Add other abort codes
                default:
                    throw new Error(`Unknown Move abort: ${abortCode[1]}`);
            }
        }
    }
    throw error;
}

try {
    await main();
} catch (error) {
    console.error("\n=== Unhandled Error ===");
    console.error("An unexpected error occurred:");
    console.error(error);
    process.exit(1);
}