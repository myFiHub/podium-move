import { deployModule } from './deploy';

const cheerConfig = {
  moduleNames: ['CheerOrBoo'],
  namedAddresses: {
    podium: '_',
    CheerOrBoo: '_',
    fihub: '_'
  },
  isDev: true
};

deployModule(cheerConfig); 