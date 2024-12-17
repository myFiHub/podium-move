import { deployModule } from './deploy';

const main = async () => {
    const isDev = process.argv.includes('--dev');
    
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