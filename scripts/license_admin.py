#!/usr/bin/env python3
"""
SpoofTrap License Administration Tool

Usage:
    python license_admin.py create --email user@example.com --plan lifetime
    python license_admin.py list
    python license_admin.py revoke STXXX-XXXXX-XXXXX-XXXXX-XXXXX
    python license_admin.py info STXXX-XXXXX-XXXXX-XXXXX-XXXXX
"""

import os
import sys
import argparse
import random
import string
import json
from datetime import datetime, timedelta

try:
    import requests
except ImportError:
    print("Installing requests...")
    os.system(f"{sys.executable} -m pip install requests -q")
    import requests

# Load from environment or .secrets file
def load_credentials():
    # Try .secrets file first
    secrets_path = os.path.join(os.path.dirname(__file__), '..', '.secrets', 'supabase.env')
    if os.path.exists(secrets_path):
        with open(secrets_path) as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
    
    return {
        'url': os.getenv('SUPABASE_URL', 'https://xucsfvyijnjkwdiiquwy.supabase.co'),
        'service_key': os.getenv('SUPABASE_SERVICE_KEY'),
        'anon_key': os.getenv('SUPABASE_ANON_KEY')
    }

CREDS = load_credentials()
SUPABASE_URL = CREDS['url']
SUPABASE_SERVICE_KEY = CREDS['service_key']

def get_headers():
    return {
        'apikey': SUPABASE_SERVICE_KEY,
        'Authorization': f'Bearer {SUPABASE_SERVICE_KEY}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
    }

def generate_license_key():
    """Generate a license key in format STXXX-XXXXX-XXXXX-XXXXX-XXXXX"""
    chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'  # Exclude confusing chars
    
    def random_segment(length):
        return ''.join(random.choice(chars) for _ in range(length))
    
    # First segment starts with ST
    key = f"ST{random_segment(3)}-{random_segment(5)}-{random_segment(5)}-{random_segment(5)}-{random_segment(5)}"
    return key

def create_license(email=None, name=None, plan='pro_monthly', activations=2, purchase_id=None, notes=None):
    """Create a new license key."""
    
    # Generate unique key
    max_attempts = 10
    for _ in range(max_attempts):
        key = generate_license_key()
        # Check if exists
        check = requests.get(
            f'{SUPABASE_URL}/rest/v1/licenses',
            headers=get_headers(),
            params={'license_key': f'eq.{key}', 'select': 'id'}
        )
        if check.status_code == 200 and len(check.json()) == 0:
            break
    else:
        print("❌ Failed to generate unique key")
        return None
    
    # Calculate expiration
    expires_at = None
    if plan == 'lifetime':
        expires_at = None
    elif plan == 'pro_monthly':
        expires_at = (datetime.utcnow() + timedelta(days=30)).isoformat()
    elif plan == 'pro_yearly':
        expires_at = (datetime.utcnow() + timedelta(days=365)).isoformat()
    elif plan == 'trial':
        expires_at = (datetime.utcnow() + timedelta(days=7)).isoformat()
    
    # Set activations based on plan
    if plan == 'lifetime':
        activations = max(activations, 3)
    
    license_data = {
        'license_key': key,
        'email': email,
        'customer_name': name,
        'plan': plan,
        'expires_at': expires_at,
        'max_activations': activations,
        'purchase_id': purchase_id,
        'notes': notes,
        'is_active': True,
        'is_revoked': False
    }
    
    response = requests.post(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        json=license_data
    )
    
    if response.status_code in [200, 201]:
        result = response.json()
        if isinstance(result, list) and len(result) > 0:
            result = result[0]
        
        print(f"\n✅ License created successfully!")
        print(f"   Key: {key}")
        print(f"   Plan: {plan}")
        print(f"   Expires: {expires_at or 'Never (Lifetime)'}")
        print(f"   Max Activations: {activations}")
        if email:
            print(f"   Email: {email}")
        return {'license_key': key, 'plan': plan, 'expires_at': expires_at}
    else:
        print(f"❌ Failed to create license: {response.status_code}")
        print(f"   Response: {response.text}")
        return None

def list_licenses(limit=50):
    """List recent licenses."""
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers={**get_headers(), 'Range': f'0-{limit-1}'},
        params={'order': 'created_at.desc', 'select': '*'}
    )
    
    if response.status_code in [200, 206]:
        licenses = response.json()
        print(f"\n📋 Recent Licenses ({len(licenses)})")
        print("-" * 90)
        print(f"{'Status':<8} {'License Key':<30} {'Plan':<12} {'Email':<25}")
        print("-" * 90)
        for lic in licenses:
            if lic['is_revoked']:
                status = "🔴"
            elif not lic['is_active']:
                status = "⚪"
            elif lic.get('expires_at') and datetime.fromisoformat(lic['expires_at'].replace('Z', '+00:00')) < datetime.now(lic['expires_at'][-6:] and None):
                status = "🟡"
            else:
                status = "🟢"
            print(f"{status:<8} {lic['license_key']:<30} {lic['plan']:<12} {lic.get('email') or '-':<25}")
        return licenses
    else:
        print(f"❌ Failed to list licenses: {response.text}")
        return []

def get_license_info(license_key):
    """Get detailed info about a license."""
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{license_key}', 'select': '*'}
    )
    
    if response.status_code == 200:
        licenses = response.json()
        if not licenses:
            print(f"❌ License not found: {license_key}")
            return None
        
        lic = licenses[0]
        print(f"\n📄 License Details")
        print("-" * 40)
        print(f"Key:           {lic['license_key']}")
        print(f"Email:         {lic.get('email') or 'Not set'}")
        print(f"Customer:      {lic.get('customer_name') or 'Not set'}")
        print(f"Plan:          {lic['plan']}")
        print(f"Created:       {lic['created_at']}")
        print(f"Expires:       {lic.get('expires_at') or 'Never (Lifetime)'}")
        print(f"Max Devices:   {lic['max_activations']}")
        print(f"Active:        {'Yes' if lic['is_active'] else 'No'}")
        print(f"Revoked:       {'Yes' if lic['is_revoked'] else 'No'}")
        if lic.get('notes'):
            print(f"Notes:         {lic['notes']}")
        
        # Get activations
        act_response = requests.get(
            f'{SUPABASE_URL}/rest/v1/activations',
            headers=get_headers(),
            params={'license_id': f"eq.{lic['id']}", 'select': '*'}
        )
        
        if act_response.status_code == 200:
            activations = act_response.json()
            active_count = sum(1 for a in activations if a['is_active'])
            print(f"\nActivations ({active_count}/{lic['max_activations']}):")
            for act in activations:
                status = "🟢" if act['is_active'] else "⚪"
                print(f"  {status} {act['platform']:<8} | {act.get('device_name') or 'Unknown':<20} | Last: {act['last_seen_at'][:10]}")
        
        return lic
    else:
        print(f"❌ Failed to get license: {response.text}")
        return None

def revoke_license(license_key, reason=None):
    """Revoke a license."""
    response = requests.patch(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{license_key}'},
        json={
            'is_revoked': True,
            'revoked_reason': reason or 'Revoked by admin'
        }
    )
    
    if response.status_code in [200, 204]:
        print(f"✅ License revoked: {license_key}")
        return True
    else:
        print(f"❌ Failed to revoke license: {response.text}")
        return False

def unrevoke_license(license_key):
    """Unrevoke a license."""
    response = requests.patch(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{license_key}'},
        json={
            'is_revoked': False,
            'revoked_reason': None
        }
    )
    
    if response.status_code in [200, 204]:
        print(f"✅ License unrevoked: {license_key}")
        return True
    else:
        print(f"❌ Failed to unrevoke license: {response.text}")
        return False

def delete_license(license_key):
    """Permanently delete a license."""
    response = requests.delete(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{license_key}'}
    )
    
    if response.status_code in [200, 204]:
        print(f"✅ License deleted: {license_key}")
        return True
    else:
        print(f"❌ Failed to delete license: {response.text}")
        return False

def main():
    parser = argparse.ArgumentParser(description='SpoofTrap License Admin')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Create command
    create_parser = subparsers.add_parser('create', help='Create a new license')
    create_parser.add_argument('--email', '-e', help='Customer email')
    create_parser.add_argument('--name', '-n', help='Customer name')
    create_parser.add_argument('--plan', '-p', default='pro_monthly',
                               choices=['trial', 'pro_monthly', 'pro_yearly', 'lifetime'])
    create_parser.add_argument('--activations', '-a', type=int, default=2, help='Max activations')
    create_parser.add_argument('--purchase-id', help='External purchase ID')
    create_parser.add_argument('--notes', help='Admin notes')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List licenses')
    list_parser.add_argument('--limit', '-l', type=int, default=50)
    
    # Info command
    info_parser = subparsers.add_parser('info', help='Get license info')
    info_parser.add_argument('key', help='License key')
    
    # Revoke command
    revoke_parser = subparsers.add_parser('revoke', help='Revoke a license')
    revoke_parser.add_argument('key', help='License key')
    revoke_parser.add_argument('--reason', '-r', help='Revocation reason')
    
    # Unrevoke command
    unrevoke_parser = subparsers.add_parser('unrevoke', help='Unrevoke a license')
    unrevoke_parser.add_argument('key', help='License key')
    
    # Delete command
    delete_parser = subparsers.add_parser('delete', help='Delete a license permanently')
    delete_parser.add_argument('key', help='License key')
    delete_parser.add_argument('--confirm', action='store_true', help='Confirm deletion')
    
    args = parser.parse_args()
    
    if not SUPABASE_SERVICE_KEY:
        print("❌ Missing Supabase credentials.")
        print("   Set SUPABASE_SERVICE_KEY or create .secrets/supabase.env")
        sys.exit(1)
    
    if args.command == 'create':
        create_license(
            email=args.email,
            name=args.name,
            plan=args.plan,
            activations=args.activations,
            purchase_id=args.purchase_id,
            notes=args.notes
        )
    elif args.command == 'list':
        list_licenses(limit=args.limit)
    elif args.command == 'info':
        get_license_info(args.key)
    elif args.command == 'revoke':
        revoke_license(args.key, reason=args.reason)
    elif args.command == 'unrevoke':
        unrevoke_license(args.key)
    elif args.command == 'delete':
        if args.confirm:
            delete_license(args.key)
        else:
            print("⚠️  Add --confirm to permanently delete the license")
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
