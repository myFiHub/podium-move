import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export interface MoveConfig {
    backup: () => void;
    restore: () => void;
    updateAddresses: (addresses: Record<string, string>) => void;
    getAddresses: () => Record<string, string>;
}

export class MoveConfigManager implements MoveConfig {
    private moveTomlPath: string;
    private backupPath: string;
    private originalContent: string | null = null;

    constructor() {
        this.moveTomlPath = path.join(__dirname, '../Move.toml');
        this.backupPath = path.join(__dirname, '../Move.toml.backup');
    }

    public backup(): void {
        this.originalContent = fs.readFileSync(this.moveTomlPath, 'utf8');
        fs.writeFileSync(this.backupPath, this.originalContent);
    }

    public restore(): void {
        if (this.originalContent) {
            fs.writeFileSync(this.moveTomlPath, this.originalContent);
            fs.unlinkSync(this.backupPath);
            this.originalContent = null;
        }
    }

    public updateAddresses(addresses: Record<string, string>): void {
        let content = fs.readFileSync(this.moveTomlPath, 'utf8');
        
        for (const [key, value] of Object.entries(addresses)) {
            const pattern = new RegExp(`(${key}\\s*=\\s*)"[^"]*"`, 'g');
            content = content.replace(pattern, `$1"${value}"`);
        }

        fs.writeFileSync(this.moveTomlPath, content);
    }

    public getAddresses(): Record<string, string> {
        const content = fs.readFileSync(this.moveTomlPath, 'utf8');
        const addresses: Record<string, string> = {};
        
        const addressRegex = /(\w+)\s*=\s*"([^"]*)"/g;
        let match;
        
        while ((match = addressRegex.exec(content)) !== null) {
            addresses[match[1]] = match[2];
        }

        return addresses;
    }
} 