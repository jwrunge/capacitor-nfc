var capacitorNFC = (function (exports, core) {
    'use strict';

    const NFCPlug = core.registerPlugin('NFC', {
        web: () => Promise.resolve().then(function () { return web; }).then((m) => new m.NFCWeb()),
    });
    const NFC = {
        isSupported: NFCPlug.isSupported.bind(NFCPlug),
        startScan: NFCPlug.startScan.bind(NFCPlug),
        cancelWriteAndroid: NFCPlug.cancelWriteAndroid.bind(NFCPlug),
        onRead: (func) => NFC.wrapperListeners.push(func),
        onWrite: (func) => NFCPlug.addListener(`nfcWriteSuccess`, func),
        onError: (errorFn) => {
            NFCPlug.addListener(`nfcError`, errorFn);
        },
        removeAllListeners: (eventName) => {
            NFC.wrapperListeners = [];
            return NFCPlug.removeAllListeners(eventName);
        },
        wrapperListeners: [],
        async writeNDEF(options) {
            var _a;
            const ndefMessage = {
                records: (_a = options === null || options === void 0 ? void 0 : options.records.map((record) => {
                    const payload = typeof record.payload === 'string'
                        ? Array.from(new TextEncoder().encode(record.payload))
                        : Array.isArray(record.payload)
                            ? record.payload
                            : record.payload instanceof Uint8Array
                                ? Array.from(record.payload)
                                : null;
                    if (!payload)
                        throw 'Unsupported payload type';
                    return {
                        type: record.type,
                        payload,
                    };
                })) !== null && _a !== void 0 ? _a : [],
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
        const fallbackDecodeWhole = () => {
            try {
                return new TextDecoder('utf-8').decode(bytes);
            }
            catch (_a) {
                return Array.from(bytes).map(b => String.fromCharCode(b)).join('');
            }
        };
        if (1 + langLength > bytes.length) {
            // Not spec-compliant; treat entire payload as plain UTF-8 text
            return fallbackDecodeWhole();
        }
        const langBytes = bytes.slice(1, 1 + langLength);
        // Validate language code is ASCII letters / hyphen; otherwise fallback
        const langValid = Array.from(langBytes).every(b => (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b === 45);
        if (!langValid)
            return fallbackDecodeWhole();
        const textBytes = bytes.slice(1 + langLength);
        try {
            const decoder = new TextDecoder(isUTF16 ? 'utf-16' : 'utf-8');
            return decoder.decode(textBytes);
        }
        catch (_a) {
            return fallbackDecodeWhole();
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
    const coercePayloadToBytes = (p) => {
        if (p instanceof Uint8Array)
            return p;
        if (Array.isArray(p) && p.every((n) => typeof n === 'number'))
            return new Uint8Array(p);
        if (typeof p === 'string') {
            // Heuristic: if it's valid base64 decode it; if not, treat as UTF-8 string content
            try {
                if (/^[A-Za-z0-9+/=]+$/.test(p) && p.length % 4 === 0) {
                    return decodeBase64ToBytes(p);
                }
            }
            catch ( /* fall through */_a) { /* fall through */ }
            // treat as plain string => encode
            return new TextEncoder().encode(p);
        }
        return new Uint8Array();
    };
    const mapPayloadTo = (type, data) => {
        return {
            messages: data.messages.map((message) => ({
                records: message.records.map((record) => {
                    const raw = record.payload; // base64 string originally, but be defensive
                    const bytes = coercePayloadToBytes(raw);
                    let payload;
                    switch (type) {
                        case 'b64': {
                            // If original was already base64, keep it; else convert bytes to base64
                            if (typeof raw === 'string' && /^[A-Za-z0-9+/=]+$/.test(raw)) {
                                payload = raw;
                            }
                            else {
                                let bin = '';
                                for (let i = 0; i < bytes.length; i++)
                                    bin += String.fromCharCode(bytes[i]);
                                payload = btoa(bin);
                            }
                            break;
                        }
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
                            payload = raw;
                    }
                    return { type: record.type, payload };
                }),
            })),
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
        for (const listener of NFC.wrapperListeners) {
            listener(wrappedData);
        }
    });

    class NFCWeb extends core.WebPlugin {
        constructor() {
            super(...arguments);
            this.wrapperListeners = [];
        }
        isSupported() {
            return Promise.resolve({ supported: false });
        }
        startScan() {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
        cancelWriteAndroid() {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
        writeNDEF() {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        onRead(_func) {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
        onWrite() {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        onError(_errorFn) {
            return Promise.reject(new Error('NFC is not supported on web'));
        }
    }

    var web = /*#__PURE__*/Object.freeze({
        __proto__: null,
        NFCWeb: NFCWeb
    });

    exports.NFC = NFC;

    Object.defineProperty(exports, '__esModule', { value: true });

    return exports;

})({}, capacitorExports);
//# sourceMappingURL=plugin.js.map
