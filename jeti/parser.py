import struct
import csv
import collections
import os
from jeti import sensors

def parse_raw(input_file, output_csv):
    """
    Extracts raw frames from a single telemetry file and dumps to CSV.
    """
    if not os.path.exists(input_file):
        print(f"Error: Could not find {input_file}")
        return
        
    with open(input_file, 'rb') as f:
        blocks = f.read()

    filename = os.path.basename(input_file)
    offset = 0
    
    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([
            'SourceFile', 
            'TimestampMs', 
            'Header2B', 
            'DeviceID', 
            'PayloadSize', 
            'PayloadHex', 
            'Ints16'
        ])
        
        while offset < len(blocks) - 3:
            type_val, size = struct.unpack('<HB', blocks[offset:offset+3])
            
            if size == 0 or size == 255:
                offset = (offset // 512 + 1) * 512
                continue
                
            if type_val == 0xfddf and size >= 10:
                data = blocks[offset+3:offset+size]
                if len(data) >= 8:
                    device_id = data[2:6].hex()
                    seq_id = data[0:2].hex()
                    timestamp = struct.unpack('<I', data[-4:])[0]
                    payload = data[6:-4]
                    
                    payload_hex = ' '.join(f'{b:02x}' for b in payload)
                    ints = []
                    if len(payload) % 2 == 0:
                        for i in range(0, len(payload), 2):
                            ints.append(str(struct.unpack('<H', payload[i:i+2])[0]))
                    int_str = ' '.join(ints) if ints else ''
                    
                    writer.writerow([
                        filename,
                        timestamp,
                        seq_id,
                        device_id,
                        len(payload),
                        payload_hex,
                        int_str
                    ])
                    
            elif type_val == 0x1ff0 and size >= 11:
                data = blocks[offset+3:offset+size]
                if len(data) > 6:
                    device_id = data[6:10].hex()
                    name_len = data[10]
                    if 11 + name_len <= len(data):
                        dev_name = data[11:11+name_len].decode('ascii', errors='ignore')
                        writer.writerow([
                            filename,
                            'DEVICE_DEF',
                            '',
                            device_id,
                            '',
                            dev_name,
                            ''
                        ])
                
            offset += size
            
    print(f"Generated {output_csv} with raw frame data.")

def parse_normalized(input_file, output_csv, hz):
    """
    Builds time-buckets of telemetry based on the sample rate.
    Uses jeti.sensors configuration to dynamically create headers and decode payloads.
    Missing data in a bucket is carried forward from the previous bucket.
    """
    if not os.path.exists(input_file):
        print(f"Error: Could not find {input_file}")
        return
        
    if hz <= 0:
        print("Error: --hz must be a positive integer.")
        return
        
    bucket_size_ms = int(1000 / hz)
    
    # Dictionary to hold the latest reading per device in each time bucket
    # Layout: data_by_time[time_bucket_ms][device_id] = payload_bytes
    data_by_time = collections.defaultdict(dict)
    
    with open(input_file, 'rb') as f:
        blocks = f.read()

    offset = 0
    min_ts = None
    max_ts = 0

    # Pass 1: Extract all data and assign to time buckets
    while offset < len(blocks) - 3:
        type_val, size = struct.unpack('<HB', blocks[offset:offset+3])
        
        if size == 0 or size == 255:
            offset = (offset // 512 + 1) * 512
            continue
            
        if type_val == 0xfddf and size >= 10:
            data = blocks[offset+3:offset+size]
            if len(data) >= 8:
                device_id = data[2:6].hex()
                payload = data[6:-4]
                timestamp_ms = struct.unpack('<I', data[-4:])[0]
                
                bucket = (timestamp_ms // bucket_size_ms) * bucket_size_ms
                
                # Only keep data if it's a sensor we know about
                if device_id in sensors.config:
                    data_by_time[bucket][device_id] = payload
                    
                if min_ts is None or bucket < min_ts:
                    min_ts = bucket
                if bucket > max_ts:
                    max_ts = bucket
                    
        offset += size

    if min_ts is None:
        print("No valid recognized telemetry data found.")
        return

    # Prepare CSV headers dynamically based on config
    headers = ['Time_Seconds'] + sensors.get_headers()
    
    # Track the last seen payload for carrying forward
    last_seen = {}
    for dev_id in sensors.config.keys():
        last_seen[dev_id] = bytes([0] * sensors.config[dev_id]['expected_length'])

    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(headers)

        for ts in range(min_ts, max_ts + bucket_size_ms, bucket_size_ms):
            sec = ts / 1000.0
            
            # Update last_seen if we have data for this bucket
            if ts in data_by_time:
                for dev_id, payload in data_by_time[ts].items():
                    last_seen[dev_id] = payload
            
            # Use sensors module to extract the flat values based on the current last_seen state
            flat_vals = sensors.get_flat_values(last_seen)
            
            # Apply formatting to floats based on type to prevent massive decimals
            # If it's a float, format it to 2 decimal places, otherwise str()
            formatted_vals = []
            for v in flat_vals:
                if isinstance(v, float):
                    formatted_vals.append(f"{v:.2f}")
                else:
                    formatted_vals.append(str(v))
                    
            row = [f"{sec:.3f}"] + formatted_vals
            writer.writerow(row)

    print(f"Generated {output_csv} spanning from {min_ts/1000.0}s to {max_ts/1000.0}s at {hz}Hz.")
