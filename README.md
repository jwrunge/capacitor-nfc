# Capacitor NFC Plugin (@exxili/capacitor-nfc)

A Capacitor plugin for reading and writing NFC tags on iOS and Android devices. This plugin allows you to:

- Read NDEF messages from NFC tags.
- Write NDEF messages to NFC tags.

**Note**: NFC functionality is only available on compatible iOS devices running iOS 13.0 or later.

## Table of Contents

- [Installation](#installation)
- [iOS Setup](#ios-setup)
- [Android Setup](#android-setup)
  - [Reading NFC Tags](#reading-nfc-tags)
  - [Writing NFC Tags](#writing-nfc-tags)
- [API](#api)
  - [Methods](#methods)
    - [`isSupported()`](#issupported)
    - [`startScan()`](#startscan)
    - [`writeNDEF(options)`](#writendefoptions-ndefwriteoptionst-extends-string--number--uint8array--string)
    - [`getUint8ArrayPayload(record)`]()
    - [`getStrPayload(record)`]()
  - [Listeners](#listeners)
    - [`addListener('nfcTag', listener)`](#addlistenernfctag-listener-data-ndefmessages--void)
    - [`addListener('nfcError', listener)`](#addlistenernfcerror-listener-error-nfcerror--void)
    - [`addListener('nfcWriteSuccess', listener)`](#addlistenernfcwritesuccess-listener---void)
  - [Interfaces](#interfaces)
    - [`NDEFWriteOptions`](#ndefwriteoptions)
    - [`NDEFMessages`](#ndefmessages)
    - [`NDEFMessage`](#ndefmessage)
    - [`NDEFRecord`](#ndefrecord)
    - [`NFCError`](#nfcerror)
- [Integration into a Capacitor App](#integration-into-a-capacitor-app)
- [Example](#example)
- [License](#license)

## Installation

Install the plugin using npm:

```bash
npm install @exxili/capacitor-nfc
npx cap sync
```

## iOS Setup

To use NFC functionality on iOS, you need to perform some additional setup steps.

### 1. Enable NFC Capability

In Xcode:

1. Open your project (`.xcworkspace` file) in Xcode.
2. Select your project in the Project Navigator.
3. Select your app target.
4. Go to the **Signing & Capabilities** tab.
5. Click the `+ Capability` button.
6. Add **Near Field Communication Tag Reading**.

### 2. Add Usage Description

Add the `NFCReaderUsageDescription` key to your `Info.plist` file to explain why your app needs access to NFC.

In your `Info.plist` file (usually located at `ios/App/App/Info.plist`), add:

```xml
<key>NFCReaderUsageDescription</key>
<string>This app requires access to NFC to read and write NFC tags.</string>
```

Replace the description with a message that explains why your app needs NFC access.

## Android Setup

Add the following to your `AndroidManifest.xml` file:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
```

## Usage

Import the plugin into your code:

```typescript
import { NFC } from '@exxili/capacitor-nfc';
```

### Reading NFC Tags

To read NFC tags, you need to start a scanning session and listen for `nfcTag` events.

```typescript
import { NFC, NDEFMessages, NFCError } from '@exxili/capacitor-nfc';

// Start NFC scanning
NFC.startScan().catch((error) => {
  console.error('Error starting NFC scan:', error);
});

// Listen for NFC tag detection
const nfcTagListener = NFC.addListener('nfcTag', (data: NDEFMessages) => {
  console.log('Received NFC tag:', data);
});

// Handle NFC errors
const nfcErrorListener = NFC.addListener('nfcError', (error: NFCError) => {
  console.error('NFC Error:', error);
});
```

### Writing NFC Tags

To write NDEF messages to NFC tags, use the `writeNDEF` method and listen for `nfcWriteSuccess` events.

```typescript
import { NFC, NDEFWriteOptions, NFCError } from '@exxili/capacitor-nfc';

const message: NDEFWriteOptions = {
  records: [
    {
      type: 'T', // Text record type
      payload: 'Hello, NFC!',
    },
  ],
};

// Write NDEF message to NFC tag
NFC.writeNDEF(message)
  .then(() => {
    console.log('Write initiated');
  })
  .catch((error) => {
    console.error('Error writing to NFC tag:', error);
  });

// Listen for write success
const nfcWriteSuccessListener = NFC.addListener('nfcWriteSuccess', () => {
  console.log('NDEF message written successfully.');
});

// Handle NFC errors
const nfcErrorListener = NFC.addListener('nfcError', (error: NFCError) => {
  console.error('NFC Error:', error);
});
```

## API

### Methods

#### `isSupported()`

Returns if NFC is supported on the scanning device.

**Returns**: `Promise<{ supported: boolean }>`

#### `startScan()`

Starts the NFC scanning session on ***iOS only***. Android devices are always in reading mode, so setting up the `nfcTag` listener is sufficient to handle tag reads on Android.

**Returns**: `Promise<void>`

```typescript
NFC.startScan()
  .then(() => {
    // Scanning started
  })
  .catch((error) => {
    console.error('Error starting NFC scan:', error);
  });
```

#### `writeNDEF(options: NDEFWriteOptions<T extends string | number[] | Uint8Array = string)`

Writes an NDEF message to an NFC tag. 

Android use: since Android has no default UI for reading and writing NFC tags, it is recommended that you add a UI indicator to your application when calling `writeNDEF` and remove it in the `nfcWriteSuccess` listener callback and the `nfcError` listener callback. This will prevent accidental writes to tags that your users intended to read from.

**Parameters**:

- `options: NDEFWriteOptions<T extends string | number[] | Uint8Array = string>` - The NDEF message to write.

**Returns**: `Promise<void>`

```typescript
NFC.writeNDEF(options)
  .then(() => {
    // Write initiated
  })
  .catch((error) => {
    console.error('Error writing NDEF message:', error);
  });
```

#### `getUint8ArrayPayload(record: NDEFRecord)`

Converts the `number[]` payload of an NDEF record to a `Uint8Array`.

**Parameters**:

- `record: NDEFRecord<number[]>` - The NDEF record to convert.

**Returns**: `Uint8Array`

#### `getStrPayload(record: NDEFRecord)`

Converts the `number[]` payload of an NDEF record to a string.

**Parameters**:

- `record: NDEFRecord<number[]>` - The NDEF record to convert.

**Returns**: `string`

### Listeners

#### `addListener('nfcTag', listener: (data: NDEFMessages) => void)`

Adds a listener for NFC tag detection events.

**Parameters**:

- `eventName: 'nfcTag'`
- `listener: (data: NDEFMessages) => void` - The function to call when an NFC tag is detected.

**Returns**: `PluginListenerHandle`

```typescript
const nfcTagListener = NFC.addListener('nfcTag', (data: NDEFMessages) => {
  console.log('Received NFC tag:', data);
});
```

#### `addListener('nfcError', listener: (error: NFCError) => void)`

Adds a listener for NFC error events.

**Parameters**:

- `eventName: 'nfcError'`
- `listener: (error: NFCError) => void` - The function to call when an NFC error occurs.

**Returns**: `PluginListenerHandle`

```typescript
const nfcErrorListener = NFC.addListener('nfcError', (error: NFCError) => {
  console.error('NFC Error:', error);
});
```

#### `addListener('nfcWriteSuccess', listener: () => void)`

Adds a listener for NFC write success events.

**Parameters**:

- `eventName: 'nfcWriteSuccess'`
- `listener: () => void` - The function to call when an NDEF message has been written successfully.

**Returns**: `PluginListenerHandle`

```typescript
const nfcWriteSuccessListener = NFC.addListener('nfcWriteSuccess', () => {
  console.log('NDEF message written successfully.');
});
```

### Interfaces

#### `NDEFWriteOptions`

Options for writing an NDEF message.

```typescript
interface NDEFWriteOptions<T extends string | number[] | Uint8Array = string> {
  records: NDEFRecord<T>[];
}
```

#### `NDEFMessages`

Data received from an NFC tag.

```typescript
interface NDEFMessages {
  messages: NDEFMessage[];
}
```

#### `NDEFMessage`

An NDEF message consisting of one or more records.

```typescript
interface NDEFMessage {
  records: NDEFRecord[];
}
```

#### `NDEFRecord`

An NDEF record. `payload` is, by default, an array of bytes representing the data; this is how an `NDEFRecord` is read from an NFC tag. You can choose to provide an `NDEFRecord` as a string a `Uint8Array` also.

```typescript
interface NDEFRecord<T = number[]> {
  /**
   * The type of the record.
   */
  type: string;

  /**
   * The payload of the record.
   */
  payload: T;
}
```

#### `NFCError`

An NFC error.

```typescript
interface NFCError {
  /**
   * The error message.
   */
  error: string;
}
```

## Integration into a Capacitor App

To integrate this plugin into your Capacitor app:

1. **Install the plugin:**

   ```bash
   npm install @exxili/capacitor-nfc
   npx cap sync
   ```

2. **Import the plugin in your code:**

   ```typescript
   import { NFC } from '@exxili/capacitor-nfc';
   ```

3. **Use the plugin methods as described in the [Usage](#usage) section.**

## Example

Here's a complete example of how to read and write NFC tags in your app:

```typescript
import { NFC, NDEFMessages, NDEFWriteOptions, NFCError } from '@exxili/capacitor-nfc';

// Check if NFC is supported
const { supported } = await NFC.isSupported();

// Start NFC scanning -- iOS only
NFC.startScan().catch((error) => {
  console.error('Error starting NFC scan:', error);
});

// Listen for NFC tag detection
const nfcTagListener = NFC.addListener('nfcTag', (data: NDEFMessages) => {
  const firstRecord = data.messages?.at(0)?.records?.at(0);
  console.log('Received NFC tag:', firstRecord); // prints number[]
  console.log('Received NFC tag:', NFC.getStrPayload(firstRecord)); // prints string
  console.log('Received NFC tag:', NFC.getUint8ArrayPayload(firstRecord)); // prints Uint8Array
});

// Handle NFC errors
const nfcErrorListener = NFC.addListener('nfcError', (error: NFCError) => {
  console.error('NFC Error:', error);
});

// Prepare an NDEF message to write
const message: NDEFWriteOptions = {
  records: [
    {
      type: 'T', // Text record type
      payload: 'Hello, NFC!',
    },
  ],
};

// Write NDEF message to NFC tag
NFC.writeNDEF(message)
  .then(() => {
    console.log('Write initiated');
  })
  .catch((error) => {
    console.error('Error writing to NFC tag:', error);
  });

// Listen for write success
const nfcWriteSuccessListener = NFC.addListener('nfcWriteSuccess', () => {
  console.log('NDEF message written successfully.');
});
```

## License

[MIT License](https://opensource.org/license/mit)

---

**Support**: If you encounter any issues or have questions, feel free to open an issue.

---
