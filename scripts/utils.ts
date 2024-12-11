import { Aptos } from "@aptos-labs/ts-sdk";

export const CHEERORBOO_ADDRESS = "0xb20104c986e1a6f6d270f82dc6694d0002401a9c4c0c7e0574845dcc59b05cb2";

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