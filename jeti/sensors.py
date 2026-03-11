import json
import os
import struct

def load_config():
    config_path = os.path.join(os.path.dirname(__file__), 'sensor_config.json')
    with open(config_path, 'r') as f:
        return json.load(f)

config = load_config()

def get_headers():
    headers = []
    # Create deterministic order of devices based on config
    # We'll just sort by the device ID keys to be consistent
    for dev_id in sorted(config.keys()):
        dev_info = config[dev_id]
        prefix = dev_info['name']
        for field in dev_info['fields']:
            headers.append(f"{prefix}_{field['name']}")
    return headers

def decode_payload(dev_id, payload):
    if dev_id not in config:
        return None
        
    dev_info = config[dev_id]
    result = {}
    
    # Pad payload if necessary
    padded_payload = list(payload)
    while len(padded_payload) < dev_info['expected_length']:
        padded_payload.append(0)
    padded_payload = bytes(padded_payload)
        
    for field in dev_info['fields']:
        offset = field['offset']
        length = field['length']
        fmt = field['type']
        scale = field['scale']
        
        if offset + length > len(padded_payload):
            result[field['name']] = 0
            continue
            
        data = padded_payload[offset:offset+length]
        
        try:
            if fmt == 'uint8':
                val = data[0]
            elif fmt == 'uint16_le':
                val = struct.unpack('<H', data)[0]
            elif fmt == 'int16_le':
                val = struct.unpack('<h', data)[0]
            elif fmt == 'uint32_le':
                val = struct.unpack('<I', data)[0]
            elif fmt == 'int32_le':
                val = struct.unpack('<i', data)[0]
            else:
                val = 0
                
            result[field['name']] = val * scale
        except Exception:
            result[field['name']] = 0
            
    return result

def get_flat_values(dev_ids_payloads):
    """
    Takes a dictionary of {dev_id: payload_bytes} and returns a flat list 
    of decoded values corresponding to get_headers() order.
    """
    row = []
    
    for dev_id in sorted(config.keys()):
        if dev_id in dev_ids_payloads:
            decoded = decode_payload(dev_id, dev_ids_payloads[dev_id])
            for field in config[dev_id]['fields']:
                row.append(decoded.get(field['name'], 0))
        else:
            # Device not present, fill with zeros
            for field in config[dev_id]['fields']:
                row.append(0)
                
    return row

def print_dictionary_sectors(img_path):
    # Print dictionary strings from continuous sectors starting at 0x2c00
    if not os.path.exists(img_path):
        print(f"Error: Could not find {img_path}")
        return
        
    # Cross reference with existing sensor config
    current_device_id = None
    
    sector_address = 0x2c00
    with open(img_path, 'rb') as f:
        while True:
            f.seek(sector_address)
            block = f.read(512)
            if not block or len(block) < 512:
                break
                
            # Stop parsing when we hit a sector that begins with 0xFF or 0x00
            if block[0] == 0xFF or block[0] == 0x00:
                break
                
            print(f"\n--- Sector at 0x{sector_address:X} ---")
            
            # Read 20-byte DictionaryEntry structures based on hexpat
            for i in range(0, 512, 20):
                chunk = block[i:i+20]
                if len(chunk) < 20: 
                    break
                    
                entry_id = chunk[0]
                
                # If we encounter 0xFF or 0x00 as ID, it's padding for the rest of the sector
                if entry_id == 0xFF or entry_id == 0x00:
                    break
                    
                if entry_id < 0x40:
                    prefix = chr(chunk[1]) if 32 <= chunk[1] <= 126 else '.'
                    name_bytes = chunk[2:16].replace(b'\x00', b'')
                    name = name_bytes.decode('ascii', errors='replace').strip()
                    
                    config_info = ""
                    if entry_id == 0x01 or entry_id == 0x00: # Device name usually starts at 01 or 00
                        # Check if this device name maps to anything in config
                        current_device_id = None
                        for dev_id, dev_info in config.items():
                            if dev_info['name'].startswith(name) or name.startswith(dev_info['name']):
                                current_device_id = dev_id
                                config_info = f" [Configured Device ID: {dev_id}]"
                                break
                    else:
                        # It's a parameter. Check if we have a matching offset in config
                        if current_device_id and current_device_id in config:
                            # Search fields for matching name
                            for field in config[current_device_id]['fields']:
                                # Try to match names loosely
                                clean_field = field['name'].replace('_V', 'V').replace('_A', 'A').replace('_mAh', 'mAh').replace('_Mins', ' times')
                                if name.lower() in field['name'].lower() or clean_field.lower() in name.lower() or name.lower().replace(' ', '') in field['name'].lower():
                                    config_info = f" [Config Offset: {field['offset']}]"
                                    break
                    
                    hex_str = ' '.join(f'{b:02x}' for b in chunk)
                    print(f"  {i:03X}: ID {entry_id:02X} | {prefix} {name:<14} | {hex_str}{config_info}")
                else:
                    hex_str = ' '.join(f'{b:02x}' for b in chunk)
                    print(f"  {i:03X}: ID {entry_id:02X} | [Device/Meta]    | {hex_str}")
                
            sector_address += 512
