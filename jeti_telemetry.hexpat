#pragma MIME application/x-jeti-sddump
#pragma endian little
#pragma pattern_limit 3000000

import std.io;
import std.mem;
import std.string;

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


// 0x1FF0 Frames: Maps a Device ID to a Human Readable Name (e.g., "MUI-30")
struct DataProfile {
    u8 unknown_padding[6] [[hidden]]; 
    u32 device_id;
    u8 name_length;
    
    // The name length varies, we dynamically read exactly 'name_length' bytes for the string
    char profile_name[name_length] [[format("format_string")]];
    u16 unknown_pad2 [[hidden]];
};


// Standard Jeti 3-byte payload tuple logic (ID, LSB, MSB)
struct MuiTuple {
    u8 id;
    u8 lsb;
    u8 msb;
    
    // Evaluate 16-bit payload
    u16 raw_value = lsb | (msb << 8);
    
    // Standard Jeti Sign Extension
    u16 value = (raw_value & 0x8000) ? -(raw_value & 0x7FFF) : raw_value;
};

// Extracts a 15-byte MUI array into five 3-byte tuples
struct MuiPayload {
    // Offset 0 (typically voltage)
    MuiTuple voltage_tuple; 
    
    // Offset 3 (typically current)
    MuiTuple current_tuple;
    
    // Offset 6 (typically capacity)
    MuiTuple capacity_tuple;
    
    // The final two tuples are usually Runtime/RPM and internal/structural data
    MuiTuple runtime_tuple;
    MuiTuple extra_tuple;
} [[format("format_mui")]];

fn format_mui(MuiPayload p) {
    return std::format("V: {}, A: {}, Cap: {}", format_voltage(p.voltage_tuple.value), format_current(p.current_tuple.value), format_capacity(p.capacity_tuple.value));
};

// Extracts an 8-byte Receiver Array
struct RxPayload {
    u8 unknown_pad1[2] [[hidden]];
    
    // Voltage is at offset 2
    u8 v_lsb;
    u8 v_msb;
    
    u8 unknown_pad2 [[hidden]]; // Offset 4
    
    // Antenna 1 is at offset 5
    u8 ant1_lsb;
    
    u8 unknown_pad3 [[hidden]]; // Offset 6
    
    // Antenna 2 is at offset 7
    u8 ant2_lsb;
} [[format("format_rx")]];

fn format_rx(RxPayload p) {
    u16 v = p.v_lsb | (p.v_msb << 8);
    u16 a1 = p.ant1_lsb;
    u16 a2 = p.ant2_lsb;
    return std::format("V: {}, Ant1: {}/9, Ant2: {}/9", format_voltage(v), a1, a2);
};


// 0xFDDF Frames: The core telemetry data packet containing sensor values
struct DataFrame {
    u16 sequence_id;
    u32 device_id;
    
    // The variable payload footprint size is defined in the parent block header (parent.size).
    // The Jeti frame 'size' metric includes the 3-byte header itself (type(2) + size(1)). 
    // The DataFrame format also contains sequence(2) + device_id(4) + timestamp(4) = 10 bytes of internal structure.
    // So the variable payload length is (parent.size - 3 (header) - 10 (internals)).
    u8 variable_payload_length = parent.size - 13;
    
    // Dynamically route the raw bytes to the correct struct analyzer
    if (variable_payload_length == 15) {
        MuiPayload mui;
    } else if (variable_payload_length == 8) {
        RxPayload rx;
    } else {
        // Fallback for unrecognized device lengths (e.g. 10 bytes, 14 bytes)
        u8 unknown_payload[variable_payload_length];
    }
    
    // The timestamp is always the last 4 bytes of a DataFrame packet
    u32 timestamp_ms;
};


// Base multiplexed frame wrapper
struct BaseFrame {
    u16 type_val; // e.g. 0x1FF0 or 0xFDDF
    u8 size;
    
    // If the size is 0x00 or 0xFF, it means we hit the padding at the end of the 512-byte sector.
    // We only try to cast a struct if size > 0 and size < 255.
    if (size > 0 && size < 255) {
        if (type_val == 0x1FF0) {
            DataProfile profile;
        } else if (type_val == 0xFDDF) {
            DataFrame frame;
        } else {
            // Unknown frame type, just consume (size - 3) bytes so we stay perfectly aligned
            // (since the size metric includes the 3 bytes of header we just consumed)
            u8 unknown_payload[size - 3] [[hidden]];
        }
    }
};


// Represents a single 512-byte sector of multiplexed logs.
// Jeti never breaks a dataframe across a sector boundary.
struct TelemetrySector {
    // Save the starting address of this sector
    u64 start_address = $;
    
    // Read frames dynamically
    // Stop reading frames if the NEXT byte sequence indicates padding (0x00 or 0xFF), or if we are out of bounds
    BaseFrame frames[while(
        $ + 2 < std::mem::size() &&
        std::mem::read_unsigned($, 1) != 0xFF && 
        std::mem::read_unsigned($, 1) != 0x00 && 
        std::mem::read_unsigned($ + 2, 1) != 0x00
    )];
    
    // Calculate how many bytes are remaining in this 512-byte sector block based on our current absolute pointer ($)
    u64 current_address = $;
    u16 bytes_consumed = current_address - start_address;
    
    // Consume the remainder of the 512-byte block to keep sector alignment perfect.
    // Make sure we never read past the actual file bounds if the extracted dump isn't a perfect multiple of 512.
    u16 padding_size = 512 - bytes_consumed;
    u64 remaining_in_file = std::mem::size() - current_address;
    
    if (remaining_in_file < padding_size) {
        padding_size = remaining_in_file;
    }
    
    if (padding_size > 0) {
        u8 sector_padding[padding_size] [[hidden]];
    }
};


// To parse a typical extracted file like '111_HYDROCAR', we just consume 512-byte 
// TelemetrySectors sequentially until we reach the end of the file.
struct FileLayout {
    TelemetrySector sectors[while(!std::mem::eof())];
};

// Map the root structure to the start of the file
FileLayout file @ 0x00;