import { Aptos, Account } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { MoveConfigManager } from './move_config.js';

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
    } catch (error: any) {
        // Don't log error for module not found during checks
        if (error?.data?.error_code !== 'module_not_found') {
            console.error(`View function failed:`, error);
        }
        return [false];
    }
}

export function getDeployerAddresses() {
    const config = yaml.parse(
        fs.readFileSync(path.join(__dirname, '../.movement/config.yaml'), 'utf-8')
    );
    const deployerAddress = config.profiles.deployer.account;

    const moveConfig = new MoveConfigManager();
    const currentAddresses = moveConfig.getAddresses();
    
    // Only update addresses that are placeholders ("_")
    const updates: Record<string, string> = {};
    for (const [key, value] of Object.entries(currentAddresses)) {
        if (value === '_') {
            updates[key] = deployerAddress;
        }
    }

    if (Object.keys(updates).length > 0) {
        moveConfig.backup();
        moveConfig.updateAddresses(updates);
    }
    
    return {
        deployerAddress,
        podiumAddress: currentAddresses.podium,
        adminAddress: currentAddresses.admin,
        treasuryAddress: currentAddresses.treasury,
        passcoinAddress: currentAddresses.passcoin
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

        return (isAdmin[0] ?? false) && (treasury[0] ?? '') === account.accountAddress;
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

export function validateAddresses(account: Account): { success: boolean; mismatches: string[] } {
    try {
        const moveToml = fs.readFileSync(path.join(__dirname, '../Move.toml'), 'utf8');
        const accountAddress = account.accountAddress.toString();
        
        // When using --dev flag, we validate against dev-addresses
        const addressSection = '[dev-addresses]';
        const devAddressesStart = moveToml.indexOf(addressSection);
        if (devAddressesStart === -1) {
            console.error('No dev-addresses section found in Move.toml');
            return { success: false, mismatches: ['dev-addresses section missing'] };
        }

        // Extract dev-addresses section
        const devAddressesText = moveToml.slice(devAddressesStart);
        const nextSection = devAddressesText.indexOf('[', addressSection.length);
        const devAddresses = devAddressesText.slice(0, nextSection > 0 ? nextSection : undefined);

        // Check if required addresses are defined
        const requiredAddresses = ['podium', 'admin', 'treasury', 'passcoin'];
        const mismatches = requiredAddresses.filter(addr => {
            const pattern = new RegExp(`${addr}\\s*=\\s*"([^"]+)"`, 'i');
            const match = devAddresses.match(pattern);
            return !match;
        });

        return {
            success: mismatches.length === 0,
            mismatches
        };
    } catch (error) {
        console.error('Error validating addresses:', error);
        return {
            success: false,
            mismatches: ['Error reading Move.toml']
        };
    }
}

export function formatAddress(address: string): string {
    // Remove '0x' prefix if present and ensure 64 characters
    const cleanAddress = address.startsWith('0x') ? address.slice(2) : address;
    return '0x' + cleanAddress.padStart(64, '0');
}

export function toMoveAmount(amount: number): string {
    return (amount * Math.pow(10, MOVE_DECIMALS)).toString();
}

export async function isModuleDeployed(aptos: Aptos, account: Account, moduleName: string): Promise<boolean> {
    try {
        const moduleExists = await aptos.getAccountModule({
            accountAddress: account.accountAddress,
            moduleName: moduleName.replace('.move', '')  // Remove .move extension
        });
        return !!moduleExists;
    } catch (error: any) {
        // Don't treat module_not_found as an error
        if (error?.data?.error_code === 'module_not_found') {
            return false;
        }
        console.error(`Error checking module deployment:`, error);
        return false;
    }
}