import { WebPlugin } from '@capacitor/core';
import type { StartScanOptions } from './definitions.js';
export declare class NFCWeb extends WebPlugin {
    isSupported(): Promise<{
        supported: boolean;
    }>;
    startScan(_options?: StartScanOptions): Promise<void>;
    cancelScan(): Promise<void>;
    cancelWriteAndroid(): Promise<void>;
    writeNDEF(): Promise<void>;
}
