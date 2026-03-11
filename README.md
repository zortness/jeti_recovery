# Jeti Disk Recovery Tool

A command-line utility for extracting, inspecting, and converting Jeti EX telemetry data from raw SD card dumps (e.g., from a JetiBox Profi).

## Overview

This tool allows you to:
1. Read the internal file table of a raw Jeti SD card dump (eg: `.img` or `.bin`).
2. Extract the embedded telemetry records into individual files.
3. Parse those extracted files into raw or normalized CSV formats.
4. Expand support for new sensor types via a simple JSON configuration.

## Usage

The main entry point is `jeti_recovery.py`. It accepts several subcommands.

### `list`
Prints the telemetry file table from a disk image.
```bash
python jeti_recovery.py list data/sd_dump.img
```

### `extract` & `extract-all`
Extracts telemetry records from the image. `extract-all` dumps everything to a folder, while `extract` grabs a specific file by its index (as seen in the `list` command).
```bash
python jeti_recovery.py extract-all data/sd_dump.img extracted_folder/
python jeti_recovery.py extract data/sd_dump.img 111 single_file.bin
```

### `parse`
Converts an extracted telemetry record into a CSV file.

**Raw output**: Dumps the raw bytes and basic header information for every data frame.
```bash
python jeti_recovery.py parse extracted_folder/111_HYDROCAR output_raw.csv --raw
```

**Normalized output**: Groups the data into time buckets, carries forward missing values, and decodes the byte payloads into human-readable units (like Volts and Amps) based on the sensor configuration.
```bash
# Outputs a 1 Hz (1 sample per second) CSV
python jeti_recovery.py parse extracted_folder/111_HYDROCAR output_1hz.csv --hz 1
```

### `print-sensors`
A diagnostic command that prints the dictionary sectors from the SD card dump, which can help correlate device IDs to their string names.
```bash
python jeti_recovery.py print-sensors data/sd_dump.img
```

## Adding New Sensors

The tool dynamically decodes EX telemetry frames based on `jeti/sensor_config.json`. To add support for a new sensor so that its data appears in the normalized CSV output, follow these steps:

1. **Identify the Device ID**: Use the `--raw` parse command or ImHex to look at the data frames. The Device ID is a 4-byte hex string (e.g., `"51a8a251"`).
2. **Determine the Payload Format**: The Jeti EX protocol sends data in a specific layout. You will need to determine the byte offset, length, and data type for each value.
3. **Update the JSON Config**: Open `jeti/sensor_config.json` and add a new entry for your Device ID.

### Config Schema

```json
{
  "device_id_hex": {
    "name": "PrefixForCSVColumns",
    "expected_length": 15,
    "fields": [
      {
        "name": "ColumnName",
        "offset": 2,          // Byte offset in the payload (0-indexed)
        "length": 1,          // Size in bytes
        "type": "uint8",      // Data type: uint8, int8, uint16_le, int16_le, uint32_le, int32_le
        "scale": 0.1          // Multiplier applied to the raw integer value
      }
    ]
  }
}
```

### Supported Data Types
- `uint8`: Unsigned 8-bit integer
- `uint16_le`: Unsigned 16-bit integer (Little Endian)
- `int16_le`: Signed 16-bit integer (Little Endian)
- `uint32_le`: Unsigned 32-bit integer (Little Endian)
- `int32_le`: Signed 32-bit integer (Little Endian)

## ImHex Patterns

This repository also includes [ImHex](https://imhex.werwolv.net/) pattern files (`*.hexpat`) that were created to visually reverse-engineer the SD card dump. These patterns allow you to interactively explore and parse the binary data structure natively in the hex editor interface.

- `jeti_sd_recovery.hexpat`: The master pattern file. When loaded against your raw `sd_dump.img`, it dynamically parses the File Table, the global Dictionary string sectors, and automatically aligns over the extracted multiplexed telemetry records. It includes custom formatting functions to display raw hex bytes as human readable volts, amps, capacities, and strings.
- Individual component files such as `jeti_dictionary.hexpat`, `jeti_file_table.hexpat`, and `jeti_telemetry.hexpat` are also retained for focused analysis of those specific data structures.

![ImHex Screenshot](https://raw.githubusercontent.com/zortness/jeti_recovery/refs/heads/main/images/imhex_proj.png)
