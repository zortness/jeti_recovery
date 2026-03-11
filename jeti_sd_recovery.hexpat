#pragma MIME application/x-jeti-sddump
#pragma endian little
#pragma pattern_limit 300000000

import std.io;
import std.mem;
import std.string;
import std.time;

// Constants from File Table Parser
#define TABLE_OFFSET 0x3D09400
#define DATA_OFFSET 0x3D19800
#define SECTOR_SIZE 512

// ==========================================
// 1. FORMATTERS
// ==========================================

// Function to clean ASCII strings natively in ImHex
fn format_string(ref auto text) {
    return std::string::replace(text, "\x00", "");
};

// Formatter to scale raw ints down by a factor of 10 for Voltage/Current (e.g., 420 -> 4.2V)
fn format_decimal(u16 val) {
    return std::format("{:.1f}", val / 10.0);
};

// Converts the raw values into text strings appending the correct units
fn format_voltage(u16 val) { return std::format("{} V", format_decimal(val)); };
fn format_current(u16 val) { return std::format("{} A", format_decimal(val)); };
fn format_capacity(u16 val) { return std::format("{} mAh", val); };
fn format_antenna(u16 val) { return std::format("{}", val); };

// Formats the 64-bit integer into a human readable date, adjusting the missing 7 years
fn format_timestamp(u64 raw_timestamp) {
    u64 corrected_time = raw_timestamp + 220903200; // adding 7 years in seconds
    std::time::TimeConverter converter; 
    converter.value = corrected_time;
    return std::time::format(converter.time, "%Y-%m-%d %H:%M:%S");
};


// ==========================================
// 2. GLOBAL DICTIONARY (dictionary.hexpat)
// ==========================================

struct DictionaryEntry {
    u8 id;
    if (id != 0xFF && id < 0x40) {
        char prefix[1] [[hidden]];
        char name[14] [[format("format_string")]];
        u32 unknown_padding [[hidden]];
    } else {
        u8 unknown_data[19] [[hidden]]; 
    }
};

struct DictionarySector {
    DictionaryEntry entries[while(std::mem::read_unsigned($, 1) != 0xFF && std::mem::read_unsigned($, 1) != 0x00)];
    u8 sector_padding[512 - sizeof(entries)] [[hidden]];
};

struct GlobalDictionary {
    DictionarySector sectors[while(std::mem::read_unsigned($, 1) != 0xFF && std::mem::read_unsigned($, 1) != 0x00)];
};

GlobalDictionary telemetry_definitions @ 0x2C00;


// ==========================================
// 3. TELEMETRY DECODER (telemetry.hexpat)
// ==========================================

struct DataProfile {
    u8 unknown_padding[6] [[hidden]]; 
    u32 device_id;
    u8 name_length;
    char profile_name[name_length] [[format("format_string")]];
    u16 unknown_pad2 [[hidden]];
};

struct MuiTuple {
    u8 id;
    u8 lsb;
    u8 msb;
    u16 raw_value = lsb | (msb << 8);
    u16 value = (raw_value & 0x8000) ? -(raw_value & 0x7FFF) : raw_value;
};

struct MuiPayload {
    MuiTuple voltage_tuple; 
    MuiTuple current_tuple;
    MuiTuple capacity_tuple;
    MuiTuple runtime_tuple;
    MuiTuple extra_tuple;
} [[format("format_mui")]];

fn format_mui(MuiPayload p) {
    return std::format("V: {}, A: {}, Cap: {}", format_voltage(p.voltage_tuple.value), format_current(p.current_tuple.value), format_capacity(p.capacity_tuple.value));
};

struct RxPayload {
    u8 unknown_pad1[2] [[hidden]];
    u8 v_lsb;
    u8 v_msb;
    u8 unknown_pad2 [[hidden]]; 
    u8 ant1_lsb;
    u8 unknown_pad3 [[hidden]];
    u8 ant2_lsb;
} [[format("format_rx")]];

fn format_rx(RxPayload p) {
    u16 v = p.v_lsb | (p.v_msb << 8);
    u16 a1 = p.ant1_lsb;
    u16 a2 = p.ant2_lsb;
    return std::format("V: {}, Ant1: {}/9, Ant2: {}/9", format_voltage(v), a1, a2);
};

struct DataFrame {
    u16 sequence_id;
    u32 device_id;
    
    u8 variable_payload_length = parent.size - 13;
    if (variable_payload_length == 15) { MuiPayload mui; }
    else if (variable_payload_length == 8) { RxPayload rx; }
    else { u8 unknown_payload[variable_payload_length]; }
    
    u32 timestamp_ms;
};

struct BaseFrame {
    u16 type_val; 
    u8 size;
    
    if (size > 0 && size < 255) {
        if (type_val == 0x1FF0) { DataProfile profile; }
        else if (type_val == 0xFDDF) { DataFrame frame; }
        else { u8 unknown_payload[size - 3] [[hidden]]; }
    }
};

struct TelemetrySector {
    u64 start_address = $;
    
    BaseFrame frames[while(
        $ + 2 < std::mem::size() &&
        std::mem::read_unsigned($, 1) != 0xFF && 
        std::mem::read_unsigned($, 1) != 0x00 && 
        std::mem::read_unsigned($ + 2, 1) != 0x00
    )];
    
    u64 current_address = $;
    u16 bytes_consumed = current_address - start_address;
    
    u16 padding_size = 512 - bytes_consumed;
    u64 remaining_in_file = std::mem::size() - current_address;
    if (remaining_in_file < padding_size) { padding_size = remaining_in_file; }
    
    if (padding_size > 0) {
        u8 sector_padding[padding_size] [[hidden]];
    }
};


// ==========================================
// 4. FILE DIRECTORY (file_table.hexpat MERGE)
// ==========================================

// Upgraded File Content parser: 
// Maps the File Size into 512-byte Telemetry Sectors dynamically!
struct TelemetryFileContent {
    u32 num_sectors = (parent.size_in_bytes + 511) / 512;
    TelemetrySector sectors[num_sectors];
};

struct FileEntry {
    u32 record_type;
    
    if (record_type == 0x8000) {
        u32 offset;
        u32 size_in_bytes;
        char profile[12] [[format("format_string")]];
        u64 raw_timestamp [[format("format_timestamp")]]; 
        
        u32 absolute_start_address = DATA_OFFSET + (offset * SECTOR_SIZE);
        
        // Dynamically span out parsed Telemetry Sectors if the file has data!
        if (size_in_bytes > 0) {
            TelemetryFileContent file_content @ absolute_start_address;
        }
    } else {
        u8 unknown_padding[28] [[hidden]]; 
    }
};

struct FileTable {
    FileEntry entries[while(std::mem::read_unsigned($, 4) == 0x8000)];
};

FileTable profi_files @ TABLE_OFFSET;