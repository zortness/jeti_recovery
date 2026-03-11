import os
import struct

TABLE_OFFSET = 0x3D09400
DATA_OFFSET = 0x3D19800
SECTOR_SIZE = 512
ENTRY_SIZE = 32

def _get_records(image_file):
    if not os.path.exists(image_file):
        raise FileNotFoundError(f"Could not find {image_file}")
        
    records = []
    with open(image_file, 'rb') as f:
        f.seek(TABLE_OFFSET)
        
        entry_idx = 0
        while True:
            entry_data = f.read(ENTRY_SIZE)
            if not entry_data or len(entry_data) < ENTRY_SIZE:
                break
                
            record_type, offset, size, profile_bytes, thing = struct.unpack('<III12sQ', entry_data)
            
            if record_type != 0x8000:
                if record_type == 0 and offset == 0:
                    break
                else:
                    entry_idx += 1
                    continue
                    
            filename = profile_bytes.decode('utf-8', errors='ignore').strip('\x00').strip()
            safe_filename = "".join([c for c in filename if c.isalpha() or c.isdigit() or c in (' ', '.', '-', '_')]).rstrip()
            if not safe_filename:
                safe_filename = f"file_{entry_idx}.bin"
                
            data_start = DATA_OFFSET + (offset * SECTOR_SIZE)
            
            records.append({
                "index": entry_idx,
                "filename": safe_filename,
                "size": size,
                "offset_block": offset,
                "data_start": data_start
            })
            entry_idx += 1
            
    return records

def list_records(image_file):
    print(f"Reading file table from {image_file}...")
    try:
        records = _get_records(image_file)
        if not records:
            print("No valid records found in the file table.")
            return
            
        print(f"{'Index':<6} | {'Filename':<20} | {'Size (bytes)':<15} | {'Offset Block'}")
        print("-" * 65)
        for rec in records:
            print(f"{rec['index']:<6} | {rec['filename']:<20} | {rec['size']:<15} | {rec['offset_block']}")
        print(f"\nFound {len(records)} records.")
    except Exception as e:
        print(f"Error reading records: {e}")

def extract_all(image_file, output_dir):
    try:
        records = _get_records(image_file)
    except Exception as e:
        print(f"Error reading records: {e}")
        return
        
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"Extracting {len(records)} files to '{output_dir}/'...")
    
    extracted_count = 0
    with open(image_file, 'rb') as f:
        for rec in records:
            f.seek(rec["data_start"])
            file_content = f.read(rec["size"])
            
            out_filename = f"{rec['index']:03d}_{rec['filename']}"
            out_path = os.path.join(output_dir, out_filename)
            
            with open(out_path, 'wb') as out_f:
                out_f.write(file_content)
            extracted_count += 1
            
    print(f"Extraction complete. {extracted_count} files extracted.")

def extract_single(image_file, record_idx, output_file):
    try:
        records = _get_records(image_file)
    except Exception as e:
        print(f"Error reading records: {e}")
        return
        
    target_rec = next((r for r in records if r["index"] == record_idx), None)
    if not target_rec:
        print(f"Error: Record index {record_idx} not found.")
        return
        
    print(f"Extracting index {record_idx} ('{target_rec['filename']}') to '{output_file}'...")
    with open(image_file, 'rb') as f:
        f.seek(target_rec["data_start"])
        file_content = f.read(target_rec["size"])
        
    with open(output_file, 'wb') as out_f:
        out_f.write(file_content)
        
    print(f"Extracted {target_rec['size']} bytes successfully.")
