import { execSync } from 'child_process';
import { getDeployerAddresses } from './utils';

interface DeployConfig {
    moduleNames: string[];
    namedAddresses: Record<string, string>;
    isDev?: boolean;
}

const deployModule = async (config: DeployConfig) => {
    try {
        // Update addresses in Move.toml using existing utility
        console.log('Updating Move.toml addresses...');
        const addresses = getDeployerAddresses();
        console.log('Using addresses:', addresses);

        // Compile with dev flag if in dev mode
        console.log('Compiling Move modules...');
        const compileCmd = `movement move compile${config.isDev ? ' --dev' : ''}`;
        execSync(compileCmd, { stdio: 'inherit' });
        
        // Publish all modules using the Movement CLI publish command
        console.log('Publishing modules...');
        const publishCmd = `movement move publish${config.isDev ? ' --dev' : ''}`;
        execSync(publishCmd, { stdio: 'inherit' });

        console.log('Deployment completed successfully!');
        return addresses;
    } catch (error) {
        console.error('Deployment failed:', error);
        throw error;
    }
};

export { deployModule }; 