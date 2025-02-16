import { Aptos, SimpleTransaction, TransactionResponse } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as path from "path";
import { getDeployerAddresses } from './utils';
import { execSync } from 'child_process';
import { createMovementClient } from './movement-config';

// Helper function to safely get transaction hash
function getTransactionHash(txn: SimpleTransaction): string {
    return (txn as unknown as { hash: string }).hash;
}

async function main() {
    try {
        // Build the package first with required flags
        console.log("Building package...");
        execSync('movement move build --save-metadata --included-artifacts all --dev --bytecode-version 6', { stdio: 'inherit' });

        // Initialize Aptos client for Movement Labs testnet
        const aptos = createMovementClient();
        
        // Get deployer address from config
        const { podiumAddress } = getDeployerAddresses();

        console.log("\nStarting deployment and upgrade process...");
        console.log(`Using account address: ${podiumAddress}`);

        // Check if account exists and create if needed
        try {
            await aptos.account.getAccountInfo({ accountAddress: podiumAddress });
            console.log("Account exists on testnet");
        } catch (error) {
            console.log("Account does not exist on testnet. Please create and fund the account first.");
            console.log("You can create an account by:");
            console.log("1. Using the Movement Labs faucet at https://fund.testnet.porto.movementlabs.xyz/");
            console.log("2. Or using the CLI: movement account create --account ${podiumAddress}");
            process.exit(1);
        }

        // First publish the package
        console.log("\nPublishing package...");
        const moduleBytecodes = [
            fs.readFileSync(path.join(process.cwd(), "build", "PodiumProtocol", "bytecode_modules", "PodiumProtocol.mv")),
            fs.readFileSync(path.join(process.cwd(), "build", "PodiumProtocol", "bytecode_modules", "CheerOrBoo.mv"))
        ];
        
        const publishTxn = await aptos.publishPackageTransaction({
            account: podiumAddress,
            metadataBytes: fs.readFileSync(path.join(process.cwd(), "build", "PodiumProtocol", "package-metadata.bcs")),
            moduleBytecode: moduleBytecodes,
            options: {
                maxGasAmount: 100000
            }
        });

        const publishHash = getTransactionHash(publishTxn);
        console.log("Initial publish transaction submitted. Transaction hash:", publishHash);
        const publishResult = await aptos.waitForTransaction({ transactionHash: publishHash });
        console.log("Initial publish completed. Transaction status:", publishResult.success ? "SUCCESS" : "FAILED");

        if (!publishResult.success) {
            throw new Error("Initial publish failed");
        }

        // Wait before upgrading
        console.log("\nWaiting 5 seconds before upgrade...");
        await new Promise(resolve => setTimeout(resolve, 5000));

        // Build again to ensure we have the latest
        console.log("\nRebuilding package for upgrade...");
        execSync('movement move build --save-metadata --included-artifacts all --dev --bytecode-version 6', { stdio: 'inherit' });

        // Now perform the upgrade
        console.log("\nPerforming upgrade...");
        const upgradeTxn = await aptos.publishPackageTransaction({
            account: podiumAddress,
            metadataBytes: fs.readFileSync(path.join(process.cwd(), "build", "PodiumProtocol", "package-metadata.bcs")),
            moduleBytecode: moduleBytecodes,
            options: {
                maxGasAmount: 100000
            }
        });

        const upgradeHash = getTransactionHash(upgradeTxn);
        console.log("Upgrade transaction submitted. Transaction hash:", upgradeHash);
        const upgradeResult = await aptos.waitForTransaction({ transactionHash: upgradeHash });
        console.log("Upgrade completed. Transaction status:", upgradeResult.success ? "SUCCESS" : "FAILED");

        if (!upgradeResult.success) {
            throw new Error("Upgrade failed");
        }

        console.log("\nDeployment and upgrade process completed successfully!");
    } catch (error) {
        console.error("Error during deployment/upgrade:", error);
        process.exit(1);
    }
}

main().catch(console.error); 