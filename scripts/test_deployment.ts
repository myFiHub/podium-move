import { main } from './deploy.js';
import { MoveConfigManager } from './move_config.js';

async function runTestDeployment() {
    const moveConfig = new MoveConfigManager();
    
    try {
        // Backup current config
        moveConfig.backup();

        // Set test addresses
        moveConfig.updateAddresses({
            podium: '0x456',
            admin: '0x123',
            treasury: '0x234',
            passcoin: '0x567'
        });

        // Run deployment with test configuration
        process.argv = [...process.argv.slice(0, 2), 'all', '--dry-run', '--dev', '--debug'];
        await main();

    } finally {
        // Restore original config
        moveConfig.restore();
    }
}

runTestDeployment().catch(console.error); 