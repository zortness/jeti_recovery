import argparse
import sys
import os

from jeti import extractor, parser, sensors

def main():
    parser_root = argparse.ArgumentParser(
        description="Jeti Disk Recovery Tool - Extract and parse Jeti EX telemetry from SD card dumps."
    )
    
    subparsers = parser_root.add_subparsers(dest="command", help="Available subcommands")
    
    # --- list ---
    parser_list = subparsers.add_parser("list", help="Print the file table (telemetry records) from the disk image.")
    parser_list.add_argument("image_file", help="Path to the raw SD card dump image file (.img, .bin, etc).")
    
    # --- extract-all ---
    parser_extract_all = subparsers.add_parser("extract-all", help="Extract all telemetry records with automatic naming.")
    parser_extract_all.add_argument("image_file", help="Path to the raw SD card dump image file.")
    parser_extract_all.add_argument("output_dir", help="Directory where extracted files will be saved.")
    
    # --- extract ---
    parser_extract = subparsers.add_parser("extract", help="Extract a single telemetry record based on its index.")
    parser_extract.add_argument("image_file", help="Path to the raw SD card dump image file.")
    parser_extract.add_argument("record_idx", type=int, help="The index of the record to extract (seen via 'list' command).")
    parser_extract.add_argument("output_file", help="Path to save the extracted record.")
    
    # --- print-sensors ---
    parser_print_sensors = subparsers.add_parser("print-sensors", help="Print the sensor definition tables/dictionary from the image.")
    parser_print_sensors.add_argument("image_file", help="Path to the raw SD card dump image file.")
    
    # --- parse ---
    parser_parse = subparsers.add_parser("parse", help="Parse a single extracted telemetry record into a CSV.")
    parser_parse.add_argument("input_file", help="Path to the extracted telemetry record file.")
    parser_parse.add_argument("output_csv", help="Path to the generated CSV output file.")
    parser_parse.add_argument("--hz", type=int, help="Output a normalized time-series CSV with decoded values at the specified sample rate (e.g., 1).", default=None)
    parser_parse.add_argument("--raw", action="store_true", help="Output raw frames in CSV format without decoding or normalization. Default behavior if --hz is omitted.")

    args = parser_root.parse_args()

    # Route to appropriate handlers
    if args.command == "list":
        extractor.list_records(args.image_file)
    elif args.command == "extract-all":
        extractor.extract_all(args.image_file, args.output_dir)
    elif args.command == "extract":
        extractor.extract_single(args.image_file, args.record_idx, args.output_file)
    elif args.command == "print-sensors":
        sensors.print_dictionary_sectors(args.image_file)
    elif args.command == "parse":
        if args.raw or args.hz is None:
            parser.parse_raw(args.input_file, args.output_csv)
        else:
            parser.parse_normalized(args.input_file, args.output_csv, args.hz)
    else:
        parser_root.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
