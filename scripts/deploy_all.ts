import { deployModule } from './deploy';

const main = async () => {
    const isDev = process.argv.includes('--dev');
    
    // Deploy all modules together since they're in the same package
    await deployModule({
        moduleNames: ['PodiumProtocol'],
        namedAddresses: {
            podium: '_',
            fihub: '_'
        },
        isDev
    });
};

main().catch(console.error); 