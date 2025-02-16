import { Aptos, Network, AptosConfig } from "@aptos-labs/ts-sdk";
import * as fs from "fs";
import * as path from "path";
import * as yaml from "yaml";

function getMovementConfig() {
    try {
        const configPath = path.join(process.cwd(), '.movement', 'config.yaml');
        const config = yaml.parse(fs.readFileSync(configPath, 'utf-8'));
        return {
            restUrl: config.rest_url || "https://aptos.testnet.porto.movementlabs.xyz/v1",
            faucetUrl: config.faucet_url || "https://fund.testnet.porto.movementlabs.xyz/"
        };
    } catch (error) {
        console.warn("Could not read Movement config, using default URLs");
        return {
            restUrl: "https://aptos.testnet.porto.movementlabs.xyz/v1",
            faucetUrl: "https://fund.testnet.porto.movementlabs.xyz/"
        };
    }
}

export function createMovementClient() {
    const config = getMovementConfig();
    const aptosConfig: AptosConfig = {
        network: Network.CUSTOM,
        fullnode: config.restUrl,
        faucet: config.faucetUrl,
        // Required by AptosConfig
        client: undefined as any,
        getRequestUrl: undefined as any,
        isIndexerRequest: undefined as any
    };
    return new Aptos(aptosConfig);
} 