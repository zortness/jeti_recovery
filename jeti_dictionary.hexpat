#pragma MIME application/x-jeti-sddump
#pragma endian little

import std.io;
import std.mem;
import std.string;

// A custom function to clean up the parameter name
fn format_name(ref auto name) {
    // In ImHex, we can use built-in string functions to just remove \0 null padding
    return std::string::replace(name, "\x00", "");
};

struct DictionaryEntry {
    u8 id;
    
    // Stop parsing string patterns if we hit the padding region (0xFF)
    // Standard telemetry parameter IDs are well under 0x40. 
    // IDs like 0x7D represent end-of-sector block metadata/device-IDs.
    if (id != 0xFF && id < 0x40) {
        char prefix[1] [[hidden]]; // Designator character (e.g. 'A', 'I', 'C', '@')
        char name[14] [[format("format_name")]];
        u32 unknown_padding [[hidden]]; // 4 bytes of 0x00 separating the 16-byte sequence
    } else {
        // If it's a metadata block like 0x7D or padding, just consume the rest of the 20-byte block 
        // to maintain alignment without throwing parsing errors.
        u8 unknown_data[19] [[hidden]]; 
    }
};

// Represents a 512-byte sector containing Dictionary entries
struct DictionarySector {
    // We read 20-byte entries sequentially.
    // If we read an ID of 0xFF or 0x00 at the start of a block, it means the rest of the sector is empty padding.
    DictionaryEntry entries[while(std::mem::read_unsigned($, 1) != 0xFF && std::mem::read_unsigned($, 1) != 0x00)];
    
    // Consume the remainder of the 512-byte sector to keep the alignment perfect.
    // (512 - the amount of bytes we just consumed into the entries array)
    u8 sector_padding[512 - sizeof(entries)] [[hidden]];
};

// Represents the entire contiguous block of dictionary sectors
struct GlobalDictionary {
    // Read sectors dynamically until we hit a sector that begins with 0xFF or 0x00 (an empty block)
    DictionarySector sectors[while(std::mem::read_unsigned($, 1) != 0xFF && std::mem::read_unsigned($, 1) != 0x00)];
};

// Based on the reference documentation, string dictionaries begin at 0x2C00:
GlobalDictionary dictionary @ 0x2C00;
