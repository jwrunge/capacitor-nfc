import { WebPlugin } from '@capacitor/core';
export class NFCWeb extends WebPlugin {
    async isSupported() {
        return { supported: false };
    }
    async startScan(_options) {
        throw new Error('NFC is not supported on web');
    }
    async cancelScan() {
        throw new Error('NFC is not supported on web');
    }
    async cancelWriteAndroid() {
        throw new Error('NFC is not supported on web');
    }
    async writeNDEF() {
        throw new Error('NFC is not supported on web');
    }
}
//# sourceMappingURL=web.js.map