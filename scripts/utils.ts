import { Aptos, Account } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Constants
export const MOVE_DECIMALS = 8;
export const PASS_DECIMALS = 8;

// Read config.yaml for deployer address
const config = yaml.parse(
    fs.readFileSync(path.join(__dirname, '../.movement/config.yaml'), 'utf-8')
);
const deployerAddress = config.profiles.deployer.account;

// Read Move.toml for FiHub address
const moveToml = fs.readFileSync(path.join(__dirname, '../Move.toml'), 'utf-8');
const fihubRegex = /fihub\s*=\s*"([^"]+)"/;

export const CHEERORBOO_ADDRESS = deployerAddress;
export const FIHUB_ADDRESS = moveToml.match(fihubRegex)?.[1] || "";

export async function isContractDeployed(aptos: Aptos, address: string) {
    try {
        const moduleData = await aptos.getAccountModule({
            accountAddress: address,
            moduleName: "CheerOrBooV2"
        });
        return moduleData !== null;
    } catch (error) {
        return false;
    }
} 

export async function viewFunction(aptos: Aptos, params: {
    function: string;
    type_arguments: string[];
    arguments: any[];
}): Promise<any[]> {
    try {
        return await aptos.view({
            payload: {
                function: params.function as `${string}::${string}::${string}`,
                typeArguments: params.type_arguments,
                functionArguments: params.arguments
            }
        });
    } catch (error) {
        console.error(`View function failed:`, error);
        return [false];
    }
}

export function getDeployerAddresses() {
    const config = yaml.parse(
        fs.readFileSync(path.join(__dirname, '../.movement/config.yaml'), 'utf-8')
    );
    const deployerAddress = config.profiles.deployer.account;

    // Update Move.toml with deployer address
    let moveToml = fs.readFileSync(path.join(__dirname, '../Move.toml'), 'utf-8');
    const addressRegex = /(podium|admin|treasury|passcoin)\s*=\s*"[^"]*"/g;
    
    moveToml = moveToml.replace(addressRegex, (match) => {
        const key = match.split('=')[0].trim();
        return `${key} = "${deployerAddress}"`;
    });

    fs.writeFileSync(path.join(__dirname, '../Move.toml'), moveToml);
    
    return {
        deployerAddress,
        podiumAddress: deployerAddress,
        adminAddress: deployerAddress,
        treasuryAddress: deployerAddress,
        passcoinAddress: deployerAddress
    };
}

export async function verifyDecimals(aptos: Aptos, account: Account): Promise<boolean> {
    try {
        const result = await aptos.view({
            payload: {
                function: `${account.accountAddress}::PodiumPassCoin::get_decimals` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });
        return result[0] === PASS_DECIMALS;
    } catch (error) {
        console.error("Decimal verification failed:", error);
        return false;
    }
}

export async function verifyOutpostCollection(aptos: Aptos, account: Account): Promise<boolean> {
    try {
        const collectionData = await aptos.view({
            payload: {
                function: `${account.accountAddress}::PodiumOutpost::get_collection_data` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });
        return !!collectionData;
    } catch (error) {
        console.error("Collection verification failed:", error);
        return false;
    }
}

export async function verifyPermissions(aptos: Aptos, account: Account): Promise<boolean> {
    try {
        // Check admin permissions
        const isAdmin = await aptos.view({
            payload: {
                function: `${account.accountAddress}::PodiumPass::is_admin` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: [account.accountAddress]
            }
        });

        // Check treasury setup
        const treasury = await aptos.view({
            payload: {
                function: `${account.accountAddress}::PodiumPass::get_treasury` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });

        return isAdmin[0] && treasury[0] === account.accountAddress;
    } catch (error) {
        console.error("Permission verification failed:", error);
        return false;
    }
}

export async function validateSystemState(aptos: Aptos, account: Account): Promise<{
    success: boolean;
    details: {
        collection: boolean;
        decimals: boolean;
        permissions: boolean;
        price: boolean;
    };
}> {
    try {
        // Verify collection
        const collectionValid = await verifyOutpostCollection(aptos, account);
        if (!collectionValid) {
            console.error("Outpost collection validation failed");
        }

        // Verify decimals
        const decimalsValid = await verifyDecimals(aptos, account);
        if (!decimalsValid) {
            console.error("Decimal configuration validation failed");
        }

        // Verify permissions
        const permissionsValid = await verifyPermissions(aptos, account);
        if (!permissionsValid) {
            console.error("Permission validation failed");
        }

        // Verify outpost price
        const outpostPrice = await aptos.view({
            payload: {
                function: `${account.accountAddress}::PodiumOutpost::get_outpost_purchase_price` as `${string}::${string}::${string}`,
                typeArguments: [],
                functionArguments: []
            }
        });
        
        const priceValid = outpostPrice[0] === toMoveAmount(30);
        if (!priceValid) {
            console.error("Outpost price validation failed");
        }

        const allValid = collectionValid && decimalsValid && permissionsValid && priceValid;

        return {
            success: allValid,
            details: {
                collection: collectionValid,
                decimals: decimalsValid,
                permissions: permissionsValid,
                price: priceValid
            }
        };
    } catch (error) {
        console.error("System state validation failed:", error);
        return {
            success: false,
            details: {
                collection: false,
                decimals: false,
                permissions: false,
                price: false
            }
        };
    }
}

export function validateAddresses(account: Account): {
    success: boolean;
    mismatches: string[];
} {
    const requiredAddresses = ['podium', 'admin', 'treasury', 'passcoin'];
    const moveToml = fs.readFileSync(path.join(__dirname, '../Move.toml'), 'utf8');
    const mismatches: string[] = [];
    
    for (const addr of requiredAddresses) {
        const regex = new RegExp(`${addr}\\s*=\\s*"([^"]+)"`, 'g');
        const match = regex.exec(moveToml);
        if (!match || match[1] !== account.accountAddress.toString()) {
            mismatches.push(addr);
        }
    }
    
    return {
        success: mismatches.length === 0,
        mismatches
    };
}

export function toMoveAmount(amount: number): string {
    return (amount * Math.pow(10, MOVE_DECIMALS)).toString();
}