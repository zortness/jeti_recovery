# Parsing Jeti EX Telemetry from Binary Dump 

This document outlines the algorithms and data structures discovered while reverse engineering a telemetry binary dump (eg: `sd_dump.img`) from a Jeti Box Profi SD Card that was starting to have issues transferring files over USB into Jeti Studio.

## Overall File Structure

The `sd_dump.img` file acts as an embedded filesystem containing a file table and multiplexed data blocks.

1.  **Block Size:** The file is structured in `512-byte` sectors.
2.  **File Table:** Located at a fixed sector offset. In this dump, it was at absolute address `0x3D09400`.
3.  **Global Dictionary Strings:** Found in the early sectors (starting at `0x2C00`). These map numeric `Parameter IDs` for each known sensor to human-readable strings like `VoltageV`, `CurrentA`, and `CapacitymAh`.
4.  **Multiplexed Data Frames:** The raw telemetry streams for different devices are interleaved across the file in defined blocks.

## 1. File Table Parsing Algorithm

The file table directory consists of contiguous entries.
*   **Entry Size:** Each entry is `32 bytes` long.

**Algorithm:**
1.  Seek to the File Table address (`0x3D09400`).
2.  Read chunks of 32 bytes sequentially.
3.  Unpack the 32-byte header:
    *   `Bytes 0-3`: Check for validity (e.g., not `0xFFFFFFFF` or `0x00000000`). Let's assume `Byte 0 = 0x01` means active file.
    *   `Bytes 4-7`: Sector Offset (Little Endian integer). This is the starting sector. To get the absolute file offset, multiply by 512 (`offset * 512`).
    *   `Bytes 8-11`: File Size in bytes (Little Endian integer).
    *   `Bytes 12-27`: Filename (ASCII, padded with nulls and whitespace).
4.  Extract the file by seeking to `Sector Offset * 512` and reading `File Size` bytes.

---

## 2. Telemetry File Frame Structure

Extracted telemetry log files (e.g., `111_HYDROCAR`) consist of multiplexed frames.

**Frame Header (3 bytes):**
1.  `Frame Type`: (Little Endian Unsigned Short, 2 bytes)
2.  `Payload Size`: (Unsigned Byte, 1 byte)

**Important Frame Types:**
*   `0x1FF0` **(Device Definitions)**: Defines the mapping of a 4-byte `Device ID` to a device name.
    *   *Payload Layout*: `[6 bytes unknown] [4 bytes Device ID] [1 byte Name Length] [ASCII String Name]`
*   `0xFDDF` **(Data Frames)**: Contains the actual telemetry readings.
    *   *Payload Layout*: `[2 bytes header/sequence] [4 bytes Device ID] [Variable Telemetry Payload] [4 bytes Timestamp in ms]`

**Algorithm for Reading Files:**
1.  Read 3 bytes `<HB` (`type_val`, `size`).
2.  If `size == 0` or `size == 255`, the current 512-byte sector boundary is reached. Skip to the start of the next 512-byte sector (`offset = (offset // 512 + 1) * 512`).
3.  Otherwise, read the next `size` bytes as the payload.
4.  Based on `type_val`, route the payload to the Definition Decoder or Data Decoder.
5.  Advance offset by `3 + size`.

---

## 3. Telemetry Payload Parsing (Jeti EX Protocol)

Inside the `0xFDDF` Data Frame, the `Telemetry Payload` contains multiplexed sensor values. 
Jeti EX payload integers are broken into chunks, natively supporting 14-bit or 22-bit precision. However, when observing the fixed layout on robust sensors like the **MUI-30**, standard patterns emerge.

### Standard Values Array (MUI Variable Blocks)
MUI devices consistently output a 15-byte long telemetry payload array structure, emitted round-robin. Instead of writing complex bit-shift masks to extract variable length arrays, the most reliable parsing dynamically splits the `15-byte` sequence into five **3-byte** tuples: `(ID, LSB, MSB)`.

**Algorithm for Interpreting 15-byte MUI Arrays:**
1.  Divide the array into chunks of 3 bytes (`m[i]`, `m[i+1]`, `m[i+2]`).
2.  Assuming standard 16-bit mappings (Little Endian): `Value = m[i+1] | (m[i+2] << 8)`.
3.  Perform **Sign Extension**: If `Value & 0x8000`, then `Value = -(Value & 0x7FFF)`.
4.  Calculate heuristic physical mappings based on absolute ranges if ID masking is obfuscated:
    *   **Voltage (V):** Often the first populated value in a subset. Typically falls between `100` and `6000` (`10.0V` to `60.0V`). Extracted via `Value / 10.0`. E.g., `420 / 10.0 = 4.2V`. (Observed consistently on `m[2]`).
    *   **Current (A):** Often the second populated parameter. Drops down to ranges like `10` or `30`. Extracted via `Value / 10.0`. E.g., `30 / 10.0 = 3.0A`. (Observed consistently on `m[5]`).
    *   **Capacity (mAh):** Usually a continuously, monotonically increasing integer. Frequently spans `0` up to `10000+`. Preserved as raw integer. (Observed consistently on `m[8]` and `m[9]`).
    *   **Runtime (s/m):** Found incrementing predictably in separate frames (Observed consistently on `m[12]` and `m[13]`).

### Standard Values Array (Rx Receiver Block)
Receivers typically output an 8-byte payload representing voltage and radio signal strengths.

**Algorithm for Interpreting 8-byte Rx Arrays:**
*   **Voltage:** Found at offset `2`. Represented as `Value / 10.0`. E.g., `59 = 5.9V`.
*   **Antenna 1:** Found at offset `5`. Signal strength scale (e.g., `0` to `9`).
*   **Antenna 2:** Found at offset `7`. Signal strength scale.

---

## References

1.  **JETI Telemetry communication protocol:** Official specification describing the EX protocol formats (both text and data forms, Little Endian).
    *   [jetimodel.com](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQFFNiOM37c6yZSOysi2-eTYE9Zv62vV1avRVot5dmqWzOpUbw2rRkphzPK1rR5KVbYWz18M5BiTaxA47OmAAPyLKmB5ohV3Q1U0JKzTTf-by7Uxf9qE48UAwJqWu5dfUyMBMeSo5LAOVhsWzUgB4oarbcQMUKLhJv726Rds4j368LER04CL54zgp3yX27ifqn1k)
2.  **EX Bus communication protocol:** Describes serial data transmission for JETI model devices bridging bidirectional setups.
    *   [jetimodel.cz](https://vertexaisearch.cloud.google.com/grounding-api-redirect/AUZIYQHBdNYKKPsx4xYgVkoO4OQ3m2GYZGuUp5bJoKzyGznYXrjmLwAMK-RUINLp7_qpnl9juv6et5fcOQxra1_nEVbNsbDAtInmVb48H1iTYZF8ty20wGlPV-4pzwM1fx0N-2ATIjpbZXz2ub6FxvdlohmloWdD8S8-zK7guTJbcTSpVjHSFQ13WXBZ0JLPbxs=)
