import * as fs from "fs";
import * as path from "path";
import * as yaml from 'yaml';

interface DependencyConfig {
    git: string;
    subdir: string;
    rev: string;
}

interface TomlStructure {
    package: {
        name: string;
        version: string;
        authors: string[];
    };
    addresses: Record<string, string>;
    "dev-addresses": Record<string, string>;
    dependencies: Record<string, DependencyConfig>;
    "dev-dependencies": Record<string, never>;
}

export class MoveConfigManager {
    private moveTomlPath: string;
    private backupPath: string;

    constructor() {
        this.moveTomlPath = path.join(process.cwd(), 'Move.toml');
        this.backupPath = path.join(process.cwd(), 'Move.toml.backup');
    }

    public getAddresses(): Record<string, string> {
        const content = fs.readFileSync(this.moveTomlPath, 'utf8');
        const addresses: Record<string, string> = {};
        
        // Extract addresses from [addresses] section
        const addressSection = content.match(/\[addresses\]([\s\S]*?)(\[|$)/);
        if (addressSection) {
            const addressLines = addressSection[1].trim().split('\n');
            addressLines.forEach(line => {
                if (line.trim() && !line.trim().startsWith('#')) {
                    const [key, value] = line.split('=').map(s => s.trim());
                    if (key && value) {
                        addresses[key] = value.replace(/"/g, '');
                    }
                }
            });
        }
        
        return addresses;
    }

    public updateAddresses(updates: Record<string, string>, isDev: boolean = true): void {
        // Create a clean TOML structure
        const toml: TomlStructure = {
            package: {
                name: "PodiumProtocol",
                version: "0.0.1",
                authors: ["FiHub"]
            },
            addresses: {},
            "dev-addresses": {},
            dependencies: {
                AptosFramework: { git: "https://github.com/aptos-labs/aptos-core.git", subdir: "aptos-move/framework/aptos-framework/", rev: "mainnet" },
                AptosStdlib: { git: "https://github.com/aptos-labs/aptos-core.git", subdir: "aptos-move/framework/aptos-stdlib/", rev: "mainnet" },
                AptosToken: { git: "https://github.com/aptos-labs/aptos-core.git", subdir: "aptos-move/framework/aptos-token/", rev: "mainnet" },
                AptosTokenObjects: { git: "https://github.com/aptos-labs/aptos-core.git", subdir: "aptos-move/framework/aptos-token-objects/", rev: "mainnet" },
                MoveStdlib: { git: "https://github.com/aptos-labs/aptos-core.git", subdir: "aptos-move/framework/move-stdlib/", rev: "mainnet" }
            },
            "dev-dependencies": {}
        };

        // Always set placeholder addresses in [addresses]
        Object.keys(updates).forEach(name => {
            toml.addresses[name] = "_";
        });

        // Set actual addresses in dev-addresses if in dev mode
        if (isDev) {
            Object.entries(updates).forEach(([name, address]) => {
                toml["dev-addresses"][name] = address;
            });
        }

        // Convert to TOML format with proper dependency formatting
        let content = `[package]
name = "${toml.package.name}"
version = "${toml.package.version}"
authors = ${JSON.stringify(toml.package.authors)}

[addresses]
${Object.entries(toml.addresses)
    .map(([name, addr]) => `${name} = "${addr}"`)
    .join('\n')}

${isDev ? `[dev-addresses]
${Object.entries(toml["dev-addresses"])
    .map(([name, addr]) => `${name} = "${addr}"`)
    .join('\n')}

` : ''}[dependencies]
${Object.entries(toml.dependencies)
    .map(([name, config]) => `${name} = { git = "${config.git}", subdir = "${config.subdir}", rev = "${config.rev}" }`)
    .join('\n')}

[dev-dependencies]
`;

        fs.writeFileSync(this.moveTomlPath, content);
    }

    public backup(): void {
        fs.copyFileSync(this.moveTomlPath, this.backupPath);
    }

    public restore(): void {
        if (fs.existsSync(this.backupPath)) {
            fs.copyFileSync(this.backupPath, this.moveTomlPath);
            fs.unlinkSync(this.backupPath);
        }
    }
} 