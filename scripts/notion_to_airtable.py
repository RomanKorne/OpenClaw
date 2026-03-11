#!/usr/bin/env python3
"""
Simple Notion -> Airtable sync utility (one-shot). Uses NOTION_API_KEY and AIRTABLE_API_KEY from env.
Adds pages' titles and links to Airtable.Memories if not present.
"""
import os,sys,json
from urllib.parse import urlparse
import requests

NOTION_TOKEN=os.environ.get('NOTION_API_KEY')
AIRTABLE_TOKEN=os.environ.get('AIRTABLE_API_KEY')
BASE='appB2VMy9GXqq0I8O'

if not NOTION_TOKEN or not AIRTABLE_TOKEN:
    print('Missing tokens')
    sys.exit(1)

def notion_search():
    url='https://api.notion.com/v1/search'
    headers={'Authorization':f'Bearer {NOTION_TOKEN}','Notion-Version':'2022-06-28','Content-Type':'application/json'}
    r=requests.post(url, headers=headers, json={})
    r.raise_for_status()
    return r.json().get('results',[])

def airtable_get_titles():
    url=f'https://api.airtable.com/v0/{BASE}/Memories'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}'}
    r=requests.get(url, headers=headers)
    r.raise_for_status()
    records=r.json().get('records',[])
    return { (rec.get('fields',{}).get('Title') or '').strip(): rec for rec in records }

def airtable_add(records):
    url=f'https://api.airtable.com/v0/{BASE}/Memories'
    headers={'Authorization':f'Bearer {AIRTABLE_TOKEN}','Content-Type':'application/json'}
    r=requests.post(url, headers=headers, json={'records':records})
    r.raise_for_status()
    return r.json()

pages=notion_search()
existing=airtable_get_titles()
to_add=[]
for p in pages:
    # Try several fallbacks for title
    title=''
    try:
        title = p.get('properties',{}).get('title',{}).get('title',[{}])[0].get('plain_text','')
    except Exception:
        title=''
    if not title:
        # fallback to url or object id
        url=p.get('url') or p.get('id')
        title = (url or '').split('/')[-1]
    title=title.strip()
    if not title or title in existing:
        continue
    link = p.get('url') or f"https://www.notion.so/{p.get('id')}"
    to_add.append({'fields':{'Title': title, 'Notion Link': link}})

if to_add:
    print('Adding', len(to_add), 'records')
    resp=airtable_add(to_add)
    print(json.dumps(resp, indent=2))
else:
    print('Nothing to add')
