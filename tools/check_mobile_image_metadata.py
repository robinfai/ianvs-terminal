#!/usr/bin/env python3
"""Validate auxiliary capture hashes and sniff dimensions from actual bytes.

Never infer PNG from the filename. --corrected writes a NEW metadata record;
raw captures, original result.json, hashes and acceptance outcomes stay frozen.
Dimensions are frame-header metadata, not a claim of full pixel/visual review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def image_info(data: bytes):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        if len(data) < 33 or data[12:16] != b'IHDR':
            raise ValueError('missing PNG IHDR')
        width, height = struct.unpack('>II', data[16:24])
        fmt = 'PNG'
    elif data.startswith(b'\xff\xd8'):
        pos = 2
        width = height = 0
        while pos < len(data):
            if data[pos] != 0xff:
                raise ValueError('invalid JPEG marker')
            while pos < len(data) and data[pos] == 0xff:
                pos += 1
            if pos >= len(data):
                break
            marker = data[pos]
            pos += 1
            if marker in (0xd9, 0xda):
                break
            if marker in range(0xd0, 0xd8) or marker == 0x01:
                continue
            if pos + 2 > len(data):
                break
            length = struct.unpack('>H', data[pos:pos + 2])[0]
            if length < 2 or pos + length > len(data):
                raise ValueError('truncated JPEG segment')
            if marker in (0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf):
                if length < 8:
                    raise ValueError('short JPEG SOF')
                height, width = struct.unpack('>HH',data[pos+3:pos+7])
                break
            pos += length
        fmt = 'JPEG'
    else:
        raise ValueError('unsupported image signature')
    if not (0 < width <= 32768 and 0 < height <= 32768):
        raise ValueError('invalid or missing dimensions')
    return fmt, width, height


def corrected_record(record, root):
    record = json.loads(json.dumps(record))
    for item in record['artifacts']:
        path = (root / item['path']).resolve()
        if not path.is_relative_to(root.resolve()):
            raise ValueError('artifact path escapes evidence root')
        if path.stat().st_size > 16*1024*1024:
            raise ValueError('image exceeds metadata-reader limit')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError(f'capture hash mismatch: {item["path"]}')
        fmt,width,height=image_info(data)
        item['pixel_size']=[width,height]
        item['image_format']=fmt
        item['dimension_method']='file_signature_and_frame_header'
        item['extension_matches_format']=path.suffix.lower() in (
            ['.png'] if fmt=='PNG' else ['.jpg','.jpeg'])
    return record


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('record',type=Path)
    parser.add_argument('--root',required=True,type=Path)
    parser.add_argument('--corrected',type=Path)
    args=parser.parse_args()
    raw=args.record.read_bytes()
    original=json.loads(raw)
    result=corrected_record(original,args.root)
    if args.corrected:
        if args.corrected.resolve()==args.record.resolve():
            parser.error('write a separate corrected record, not the frozen original')
        result['metadata_correction']={
            'source_record_sha256':hashlib.sha256(raw).hexdigest(),
            'note':'Dimensions/format corrected from image headers; no images or acceptance statuses changed.',
        }
        args.corrected.parent.mkdir(parents=True,exist_ok=True)
        args.corrected.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    else:
        mismatches=[item['path'] for item,fixed in zip(original['artifacts'],result['artifacts'])
                    if item.get('pixel_size')!=fixed['pixel_size']]
        if mismatches:
            raise SystemExit('Incorrect dimensions: '+', '.join(mismatches))
    print(json.dumps([{'path':i['path'],'format':i['image_format'],'pixel_size':i['pixel_size']}
                      for i in result['artifacts']],ensure_ascii=False))

if __name__=='__main__':
    main()
