import { WebPlugin } from '@capacitor/core';
export declare class NFCWeb extends WebPlugin {
    isSupported(): Promise<{
        supported: boolean;
    }>;
    startScan(): Promise<void>;
    cancelScan(): Promise<void>;
    cancelWriteAndroid(): Promise<void>;
    writeNDEF(): Promise<void>;
}
