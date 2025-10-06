'use strict';

var __createBinding = (undefined && undefined.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (undefined && undefined.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var _a, _b;
Object.defineProperty(exports, "__esModule", { value: true });
exports.NFC = void 0;
const core_1$1 = require("@capacitor/core");
const NFCPlug = (0, core_1$1.registerPlugin)('NFC', {
    // Explicit .js extension required under node16/nodenext module resolution for emitted ES modules.
    web: () => Promise.resolve().then(function () { return web; }).then((m) => new m.NFCWeb()),
});
__exportStar(require("./definitions"), exports);
exports.NFC = {
    isSupported: NFCPlug.isSupported.bind(NFCPlug),
    startScan: NFCPlug.startScan.bind(NFCPlug),
    cancelScan: (_b = (_a = NFCPlug.cancelScan) === null || _a === void 0 ? void 0 : _a.bind(NFCPlug)) !== null && _b !== void 0 ? _b : (async () => {
        /* Android no-op */
    }),
    cancelWriteAndroid: NFCPlug.cancelWriteAndroid.bind(NFCPlug),
    onRead: (func) => {
        exports.NFC.wrapperListeners.push(func);
        // Return unsubscribe function
        return () => {
            exports.NFC.wrapperListeners = exports.NFC.wrapperListeners.filter((l) => l !== func);
        };
    },
    onWrite: (func) => {
        let handle;
        NFCPlug.addListener(`nfcWriteSuccess`, func).then((h) => (handle = h));
        return () => {
            var _a;
            try {
                (_a = handle === null || handle === void 0 ? void 0 : handle.remove) === null || _a === void 0 ? void 0 : _a.call(handle);
            }
            catch (_b) {
                /* empty */
            }
        };
    },
    onError: (errorFn) => {
        let handle;
        NFCPlug.addListener(`nfcError`, errorFn).then((h) => (handle = h));
        return () => {
            var _a;
            try {
                (_a = handle === null || handle === void 0 ? void 0 : handle.remove) === null || _a === void 0 ? void 0 : _a.call(handle);
            }
            catch (_b) {
                /* empty */
            }
        };
    },
    removeAllListeners: (eventName) => {
        exports.NFC.wrapperListeners = [];
        return NFCPlug.removeAllListeners(eventName);
    },
    wrapperListeners: [],
    async writeNDEF(options) {
        var _a;
        // Helper encoders for well-known record types (only applied to string payloads)
        const buildTextPayload = (text, lang = 'en') => {
            const langBytes = Array.from(new TextEncoder().encode(lang));
            const textBytes = Array.from(new TextEncoder().encode(text));
            const status = langBytes.length & 0x3f; // UTF-8 encoding, language length (<= 63)
            return [status, ...langBytes, ...textBytes];
        };
        const buildUriPayload = (uri, prefixCode = 0x00) => {
            const uriBytes = Array.from(new TextEncoder().encode(uri));
            return [prefixCode, ...uriBytes];
        };
        const recordsArray = (_a = options === null || options === void 0 ? void 0 : options.records) !== null && _a !== void 0 ? _a : [];
        if (recordsArray.length === 0)
            throw new Error('At least one NDEF record is required');
        const ndefMessage = {
            records: recordsArray.map((record) => {
                let payload = null;
                if (typeof record.payload === 'string') {
                    // Apply spec-compliant formatting only for Well Known Text (T) & URI (U) types.
                    if (record.type === 'T') {
                        payload = buildTextPayload(record.payload);
                    }
                    else if (record.type === 'U') {
                        payload = buildUriPayload(record.payload);
                    }
                    else {
                        // Generic string: raw UTF-8 bytes (no extra framing)
                        payload = Array.from(new TextEncoder().encode(record.payload));
                    }
                }
                else if (Array.isArray(record.payload)) {
                    // Assume already raw bytes; do NOT modify
                    payload = record.payload;
                }
                else if (record.payload instanceof Uint8Array) {
                    payload = Array.from(record.payload);
                }
                if (!payload)
                    throw new Error('Unsupported payload type');
                return { type: record.type, payload };
            }),
        };
        await NFCPlug.writeNDEF(ndefMessage);
    },
};
// Decode a base64 string into a Uint8Array (browser-safe). Existing code used atob already.
const decodeBase64ToBytes = (base64Payload) => {
    const bin = atob(base64Payload);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++)
        out[i] = bin.charCodeAt(i);
    return out;
};
// Parse NFC Forum "Text" (Well Known 'T') records according to spec.
const decodeTextRecord = (bytes) => {
    if (bytes.length === 0)
        return '';
    const status = bytes[0];
    const isUTF16 = (status & 0x80) !== 0; // Bit 7 indicates encoding
    const langLength = status & 0x3f; // Bits 0-5 language code length
    if (1 + langLength > bytes.length)
        return ''; // Corrupt
    const textBytes = bytes.slice(1 + langLength);
    try {
        const decoder = new TextDecoder(isUTF16 ? 'utf-16' : 'utf-8');
        return decoder.decode(textBytes);
    }
    catch (_a) {
        // Fallback: naive ASCII
        return Array.from(textBytes)
            .map((b) => String.fromCharCode(b))
            .join('');
    }
};
// Basic URI prefix table for Well Known 'U' records (optional convenience)
const URI_PREFIX = [
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
    'tel:',
    'mailto:',
    'ftp://anonymous:anonymous@',
    'ftp://ftp.',
    'ftps://',
    'sftp://',
    'smb://',
    'nfs://',
    'ftp://',
    'dav://',
    'news:',
    'telnet://',
    'imap:',
    'rtsp://',
    'urn:',
    'pop:',
    'sip:',
    'sips:',
    'tftp:',
    'btspp://',
    'btl2cap://',
    'btgoep://',
    'tcpobex://',
    'irdaobex://',
    'file://',
    'urn:epc:id:',
    'urn:epc:tag:',
    'urn:epc:pat:',
    'urn:epc:raw:',
    'urn:epc:',
    'urn:nfc:',
];
const decodeUriRecord = (bytes) => {
    if (bytes.length === 0)
        return '';
    const prefixIndex = bytes[0];
    const prefix = URI_PREFIX[prefixIndex] || '';
    const remainder = bytes.slice(1);
    try {
        return prefix + new TextDecoder('utf-8').decode(remainder);
    }
    catch (_a) {
        return (prefix +
            Array.from(remainder)
                .map((b) => String.fromCharCode(b))
                .join(''));
    }
};
const toStringPayload = (recordType, bytes) => {
    // Well Known Text
    if (recordType === 'T')
        return decodeTextRecord(bytes);
    // Well Known URI
    if (recordType === 'U')
        return decodeUriRecord(bytes);
    // Default: attempt UTF-8 decode
    try {
        return new TextDecoder('utf-8').decode(bytes);
    }
    catch (_a) {
        return Array.from(bytes)
            .map((c) => String.fromCharCode(c))
            .join('');
    }
};
const mapPayloadTo = (type, data) => {
    return {
        messages: data.messages.map((message) => ({
            records: message.records.map((record) => {
                const bytes = decodeBase64ToBytes(record.payload);
                let payload;
                switch (type) {
                    case 'b64':
                        payload = record.payload; // original base64 string
                        break;
                    case 'uint8Array':
                        payload = bytes;
                        break;
                    case 'numberArray':
                        payload = Array.from(bytes);
                        break;
                    case 'string':
                        payload = toStringPayload(record.type, bytes);
                        break;
                    default:
                        payload = record.payload;
                }
                return { type: record.type, payload };
            }),
        })),
        tagInfo: data.tagInfo, // Include tag information
    };
};
NFCPlug.addListener(`nfcTag`, (data) => {
    const wrappedData = {
        base64() {
            return mapPayloadTo('b64', data);
        },
        string() {
            return mapPayloadTo('string', data);
        },
        uint8Array() {
            return mapPayloadTo('uint8Array', data);
        },
        numberArray() {
            return mapPayloadTo('numberArray', data);
        },
    };
    for (const listener of exports.NFC.wrapperListeners) {
        listener(wrappedData);
    }
});

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

var web = /*#__PURE__*/Object.freeze({
    __proto__: null
});
//# sourceMappingURL=plugin.cjs.js.map
