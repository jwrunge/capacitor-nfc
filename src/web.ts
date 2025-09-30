import { WebPlugin } from '@capacitor/core';

export class NFCWeb extends WebPlugin {
  async isSupported(): Promise<{ supported: boolean }> {
    return { supported: false };
  }

  async startScan(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async cancelScan(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async cancelWriteAndroid(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }

  async writeNDEF(): Promise<void> {
    throw new Error('NFC is not supported on web');
  }
}
