"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NFCWeb = void 0;
const core_1 = require("@capacitor/core");
class NFCWeb extends core_1.WebPlugin {
    async isSupported() {
        return { supported: false };
    }
    async startScan() {
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
exports.NFCWeb = NFCWeb;
//# sourceMappingURL=web.js.map