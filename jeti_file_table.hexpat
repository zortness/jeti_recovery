#pragma MIME application/x-jeti-sddump
#pragma endian little

import std.io;
import std.mem;
import std.string;
import std.time;

// Based on extract_race.py
#define TABLE_OFFSET 0x3D09400
#define DATA_OFFSET 0x3D19800
#define SECTOR_SIZE 512

// Basic timestamp offset. 7 years roughly = 220,903,200 seconds. 
// We will apply this dynamically.
// A custom function to clean up the profile name
fn format_filename(ref auto profile) {
    // In ImHex, we can use built-in string functions to just remove \0
    return std::string::replace(profile, "\x00", "");
};

// Formats the 64-bit integer into a human readable date, assuming it's a Unix timestamp 
// that is erroneously shifted backward by ~7 years.
fn format_timestamp(u64 raw_timestamp) {
    u64 corrected_time = raw_timestamp + 220903200; // adding 7 years in seconds
    
    // ImHex's std::time::format requires a std::time::Time struct, not an integer.
    // We use the TimeConverter union as prescribed in time.pat to cast from u128 down to Time.
    std::time::TimeConverter converter; 
    converter.value = corrected_time;
    
    return std::time::format(converter.time, "%Y-%m-%d %H:%M:%S");
};

// Represents the telemetry data file content.
// By pointing to this, expanding it jumps the cursor to this absolute offset.
struct TelemetryFileContent {
    u8 raw_data[parent.size_in_bytes];
};

struct FileEntry {
    u32 record_type;
    
    // Check if this is a valid record type (0x8000). 
    // If it's valid, we unpack the rest of the 32 bytes.
    if (record_type == 0x8000) {
        u32 offset;
        u32 size_in_bytes;
        char profile[12] [[format("format_filename")]];
        
        // This is a timestamp, but off by 7 years (220,903,200 seconds).
        // Using an inline function to add the offset before passing to ImHex's datetime formatter
        u64 raw_timestamp [[format("format_timestamp")]]; 
        
        // Calculate the absolute pointer where this file's data begins.
        // The offset field multiplied by 512, plus the start directory offset of 0x3D19800
        u32 absolute_start_address = DATA_OFFSET + (offset * SECTOR_SIZE);
        
        // Let's create an interactive pointer exactly where the data lives.
        // It's conditionally formatted so it only shows up if size > 0.
        if (size_in_bytes > 0) {
            TelemetryFileContent file_content @ absolute_start_address;
        }
    } else {
        // If not 0x8000, we still need to consume 28 bytes to keep the 32-byte alignment 
        // in case we just want to skip it without failing pattern matching.
        u8 unknown_padding[28] [[hidden]]; 
    }
};

// A recursive structural array that will keep parsing FileEntry blocks 
// until it hits an invalid record type.
struct FileTable {
    FileEntry entries[while(std::mem::read_unsigned($, 4) == 0x8000)];
};

// Place the structure definition at the fixed File Table offset in sd_dump.img
FileTable profi_files @ TABLE_OFFSET;