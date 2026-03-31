#!/usr/bin/env python3
"""
SpoofTrap License Bot for Discord

Commands:
    /license create <email> <plan>  - Create a new license
    /license info <key>             - Get license details
    /license list                   - List recent licenses
    /license revoke <key> [reason]  - Revoke a license
    /license unrevoke <key>         - Restore a revoked license

Setup:
    1. Create a Discord bot at https://discord.com/developers/applications
    2. Enable "Message Content Intent" in Bot settings
    3. Copy the bot token
    4. Add to .secrets/discord.env:
       DISCORD_BOT_TOKEN=your_token_here
       ADMIN_ROLE_ID=your_admin_role_id (optional)
    5. Invite bot with: https://discord.com/oauth2/authorize?client_id=YOUR_APP_ID&permissions=2147485696&scope=bot%20applications.commands
    6. Run: python3 scripts/discord_bot.py
"""

import os
import sys
import random
from datetime import datetime, timedelta

# Install dependencies if needed
try:
    import discord
    from discord import app_commands
except ImportError:
    print("Installing discord.py...")
    os.system(f"{sys.executable} -m pip install discord.py -q")
    import discord
    from discord import app_commands

try:
    import requests
except ImportError:
    os.system(f"{sys.executable} -m pip install requests -q")
    import requests

# Load credentials - supports both local .secrets files and Railway env vars
def load_env(filename):
    path = os.path.join(os.path.dirname(__file__), '..', '.secrets', filename)
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    if key not in os.environ:  # Don't override Railway env vars
                        os.environ[key] = value

load_env('supabase.env')
load_env('discord.env')

DISCORD_TOKEN = os.getenv('DISCORD_BOT_TOKEN')
ADMIN_ROLE_ID = os.getenv('ADMIN_ROLE_ID')
SUPABASE_URL = os.getenv('SUPABASE_URL', 'https://xucsfvyijnjkwdiiquwy.supabase.co')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')

if not DISCORD_TOKEN:
    print("❌ Missing DISCORD_BOT_TOKEN in .secrets/discord.env")
    sys.exit(1)

if not SUPABASE_SERVICE_KEY:
    print("❌ Missing Supabase credentials in .secrets/supabase.env")
    sys.exit(1)

def get_headers():
    return {
        'apikey': SUPABASE_SERVICE_KEY,
        'Authorization': f'Bearer {SUPABASE_SERVICE_KEY}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
    }

def generate_license_key():
    chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    def seg(n): return ''.join(random.choice(chars) for _ in range(n))
    return f"ST{seg(3)}-{seg(5)}-{seg(5)}-{seg(5)}-{seg(5)}"

class LicenseBot(discord.Client):
    def __init__(self):
        intents = discord.Intents.default()
        super().__init__(intents=intents)
        self.tree = app_commands.CommandTree(self)
    
    async def setup_hook(self):
        await self.tree.sync()
        print(f"✅ Synced {len(self.tree.get_commands())} commands")

client = LicenseBot()

def is_admin():
    async def predicate(interaction: discord.Interaction) -> bool:
        if ADMIN_ROLE_ID:
            role = discord.utils.get(interaction.user.roles, id=int(ADMIN_ROLE_ID))
            if not role:
                await interaction.response.send_message("❌ You need admin role to use this.", ephemeral=True)
                return False
        return True
    return app_commands.check(predicate)

license_group = app_commands.Group(name="license", description="License management commands")

@license_group.command(name="create", description="Create a new license key")
@is_admin()
@app_commands.describe(
    email="Customer email address",
    plan="License plan type",
    activations="Max device activations (default: 2)"
)
@app_commands.choices(plan=[
    app_commands.Choice(name="Trial (7 days)", value="trial"),
    app_commands.Choice(name="Pro Monthly", value="pro_monthly"),
    app_commands.Choice(name="Pro Yearly", value="pro_yearly"),
    app_commands.Choice(name="Lifetime", value="lifetime"),
])
async def create_license(interaction: discord.Interaction, email: str, plan: str, activations: int = 2):
    await interaction.response.defer(ephemeral=True)
    
    # Generate unique key
    for _ in range(10):
        key = generate_license_key()
        check = requests.get(
            f'{SUPABASE_URL}/rest/v1/licenses',
            headers=get_headers(),
            params={'license_key': f'eq.{key}', 'select': 'id'}
        )
        if check.status_code == 200 and len(check.json()) == 0:
            break
    else:
        await interaction.followup.send("❌ Failed to generate unique key", ephemeral=True)
        return
    
    # Calculate expiration
    expires_at = None
    if plan == 'trial':
        expires_at = (datetime.utcnow() + timedelta(days=7)).isoformat()
    elif plan == 'pro_monthly':
        expires_at = (datetime.utcnow() + timedelta(days=30)).isoformat()
    elif plan == 'pro_yearly':
        expires_at = (datetime.utcnow() + timedelta(days=365)).isoformat()
    
    if plan == 'lifetime':
        activations = max(activations, 3)
    
    license_data = {
        'license_key': key,
        'email': email,
        'plan': plan,
        'expires_at': expires_at,
        'max_activations': activations,
        'is_active': True,
        'is_revoked': False,
        'notes': f'Created by {interaction.user.name} via Discord'
    }
    
    response = requests.post(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        json=license_data
    )
    
    if response.status_code in [200, 201]:
        embed = discord.Embed(
            title="✅ License Created",
            color=discord.Color.green()
        )
        embed.add_field(name="License Key", value=f"```{key}```", inline=False)
        embed.add_field(name="Email", value=email, inline=True)
        embed.add_field(name="Plan", value=plan.replace('_', ' ').title(), inline=True)
        embed.add_field(name="Expires", value=expires_at[:10] if expires_at else "Never", inline=True)
        embed.add_field(name="Max Devices", value=str(activations), inline=True)
        embed.set_footer(text=f"Created by {interaction.user.name}")
        
        await interaction.followup.send(embed=embed, ephemeral=True)
    else:
        await interaction.followup.send(f"❌ Failed to create license: {response.text}", ephemeral=True)

@license_group.command(name="info", description="Get license details")
@is_admin()
@app_commands.describe(key="License key to look up")
async def license_info(interaction: discord.Interaction, key: str):
    await interaction.response.defer(ephemeral=True)
    
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{key.upper()}', 'select': '*'}
    )
    
    if response.status_code != 200 or not response.json():
        await interaction.followup.send(f"❌ License not found: `{key}`", ephemeral=True)
        return
    
    lic = response.json()[0]
    
    # Get activations
    act_response = requests.get(
        f'{SUPABASE_URL}/rest/v1/activations',
        headers=get_headers(),
        params={'license_id': f"eq.{lic['id']}", 'select': '*', 'is_active': 'eq.true'}
    )
    activations = act_response.json() if act_response.status_code == 200 else []
    
    # Status
    if lic['is_revoked']:
        status = "🔴 Revoked"
        color = discord.Color.red()
    elif not lic['is_active']:
        status = "⚪ Inactive"
        color = discord.Color.greyple()
    elif lic.get('expires_at') and datetime.fromisoformat(lic['expires_at'].replace('Z', '+00:00').replace('+00:00', '')) < datetime.utcnow():
        status = "🟡 Expired"
        color = discord.Color.yellow()
    else:
        status = "🟢 Active"
        color = discord.Color.green()
    
    embed = discord.Embed(title="License Details", color=color)
    embed.add_field(name="Key", value=f"```{lic['license_key']}```", inline=False)
    embed.add_field(name="Status", value=status, inline=True)
    embed.add_field(name="Plan", value=lic['plan'].replace('_', ' ').title(), inline=True)
    embed.add_field(name="Email", value=lic.get('email') or 'N/A', inline=True)
    embed.add_field(name="Created", value=lic['created_at'][:10], inline=True)
    embed.add_field(name="Expires", value=lic['expires_at'][:10] if lic.get('expires_at') else 'Never', inline=True)
    embed.add_field(name="Devices", value=f"{len(activations)}/{lic['max_activations']}", inline=True)
    
    if activations:
        devices = "\n".join([f"• {a['platform']} - {a.get('device_name', 'Unknown')}" for a in activations[:5]])
        embed.add_field(name="Active Devices", value=devices, inline=False)
    
    if lic.get('revoked_reason'):
        embed.add_field(name="Revoke Reason", value=lic['revoked_reason'], inline=False)
    
    await interaction.followup.send(embed=embed, ephemeral=True)

@license_group.command(name="list", description="List recent licenses")
@is_admin()
@app_commands.describe(limit="Number of licenses to show (default: 10)")
async def list_licenses(interaction: discord.Interaction, limit: int = 10):
    await interaction.response.defer(ephemeral=True)
    
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers={**get_headers(), 'Range': f'0-{min(limit, 25)-1}'},
        params={'order': 'created_at.desc', 'select': '*'}
    )
    
    if response.status_code not in [200, 206]:
        await interaction.followup.send(f"❌ Failed to fetch licenses", ephemeral=True)
        return
    
    licenses = response.json()
    
    if not licenses:
        await interaction.followup.send("No licenses found.", ephemeral=True)
        return
    
    embed = discord.Embed(
        title=f"📋 Recent Licenses ({len(licenses)})",
        color=discord.Color.blue()
    )
    
    lines = []
    for lic in licenses:
        if lic['is_revoked']:
            status = "🔴"
        elif not lic['is_active']:
            status = "⚪"
        else:
            status = "🟢"
        
        email_short = (lic.get('email') or 'N/A')[:20]
        lines.append(f"{status} `{lic['license_key'][:15]}...` | {lic['plan'][:8]} | {email_short}")
    
    embed.description = "\n".join(lines)
    await interaction.followup.send(embed=embed, ephemeral=True)

@license_group.command(name="revoke", description="Revoke a license")
@is_admin()
@app_commands.describe(key="License key to revoke", reason="Reason for revocation")
async def revoke_license(interaction: discord.Interaction, key: str, reason: str = "Revoked via Discord"):
    await interaction.response.defer(ephemeral=True)
    
    response = requests.patch(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{key.upper()}'},
        json={'is_revoked': True, 'revoked_reason': f"{reason} (by {interaction.user.name})"}
    )
    
    if response.status_code in [200, 204]:
        embed = discord.Embed(
            title="🔴 License Revoked",
            description=f"```{key.upper()}```",
            color=discord.Color.red()
        )
        embed.add_field(name="Reason", value=reason)
        embed.set_footer(text=f"Revoked by {interaction.user.name}")
        await interaction.followup.send(embed=embed, ephemeral=True)
    else:
        await interaction.followup.send(f"❌ Failed to revoke license", ephemeral=True)

@license_group.command(name="unrevoke", description="Restore a revoked license")
@is_admin()
@app_commands.describe(key="License key to restore")
async def unrevoke_license(interaction: discord.Interaction, key: str):
    await interaction.response.defer(ephemeral=True)
    
    response = requests.patch(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=get_headers(),
        params={'license_key': f'eq.{key.upper()}'},
        json={'is_revoked': False, 'revoked_reason': None}
    )
    
    if response.status_code in [200, 204]:
        embed = discord.Embed(
            title="🟢 License Restored",
            description=f"```{key.upper()}```",
            color=discord.Color.green()
        )
        embed.set_footer(text=f"Restored by {interaction.user.name}")
        await interaction.followup.send(embed=embed, ephemeral=True)
    else:
        await interaction.followup.send(f"❌ Failed to restore license", ephemeral=True)

client.tree.add_command(license_group)

@client.event
async def on_ready():
    print(f"🤖 {client.user} is online!")
    print(f"   Servers: {len(client.guilds)}")
    print(f"   Commands: /license create, /license info, /license list, /license revoke, /license unrevoke")

if __name__ == '__main__':
    print("Starting SpoofTrap License Bot...")
    client.run(DISCORD_TOKEN)
