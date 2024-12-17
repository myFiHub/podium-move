import { Aptos } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as yaml from "yaml";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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