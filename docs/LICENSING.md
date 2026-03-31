# SpoofTrap Licensing System

Complete implementation guide for the SpoofTrap license key system using Supabase.

---

## Table of Contents

1. [Overview](#overview)
2. [Supabase Setup](#supabase-setup)
3. [Database Schema](#database-schema)
4. [API Endpoints](#api-endpoints)
5. [License Key Format](#license-key-format)
6. [Device ID Generation](#device-id-generation)
7. [macOS Implementation](#macos-implementation)
8. [Windows Implementation](#windows-implementation)
9. [Admin Tools](#admin-tools)
10. [Security](#security)
11. [Testing](#testing)

---

## Overview

### Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   macOS App     │────▶│    Supabase     │◀────│  Windows App    │
│   (Swift)       │     │  (PostgreSQL)   │     │  (C#/WinUI)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │  Admin Panel    │
                        │  (Web/Script)   │
                        └─────────────────┘
```

### Flow

1. User purchases license → receives key via email
2. User enters key in app → app sends to Supabase
3. Supabase validates key, checks activations
4. If valid, device is registered and app unlocks
5. Periodic heartbeat keeps license active

### Plans

| Plan | Duration | Activations | Price (suggested) |
|------|----------|-------------|-------------------|
| Pro Monthly | 30 days | 2 devices | $4.99/mo |
| Pro Yearly | 365 days | 2 devices | $29.99/yr |
| Lifetime | Forever | 3 devices | $49.99 |

---

## Supabase Setup

### Step 1: Create Project

1. Go to [supabase.com](https://supabase.com)
2. Create new project
3. Save these credentials:
   - **Project URL**: `https://xxxxx.supabase.co`
   - **Anon Key**: `eyJhbGciOiJI...` (public, safe for client)
   - **Service Key**: `eyJhbGciOiJI...` (secret, admin only)

### Step 2: Environment Variables

Create `.secrets/supabase.env`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Step 3: Run Database Migrations

Execute the SQL in [Database Schema](#database-schema) section via Supabase SQL Editor.

---

## Database Schema

### Run in Supabase SQL Editor

```sql
-- ============================================
-- SPOOFTRAP LICENSE SYSTEM - DATABASE SCHEMA
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- LICENSES TABLE
-- ============================================
CREATE TABLE licenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_key VARCHAR(29) UNIQUE NOT NULL,
    email VARCHAR(255),
    customer_name VARCHAR(100),
    plan VARCHAR(20) NOT NULL DEFAULT 'pro',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    max_activations INT DEFAULT 2,
    is_active BOOLEAN DEFAULT true,
    is_revoked BOOLEAN DEFAULT false,
    revoked_reason TEXT,
    purchase_id VARCHAR(100),
    notes TEXT,
    
    CONSTRAINT valid_plan CHECK (plan IN ('trial', 'pro_monthly', 'pro_yearly', 'lifetime'))
);

-- ============================================
-- ACTIVATIONS TABLE
-- ============================================
CREATE TABLE activations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_id UUID NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    device_name VARCHAR(100),
    platform VARCHAR(20) NOT NULL,
    app_version VARCHAR(20),
    os_version VARCHAR(50),
    activated_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_ip INET,
    is_active BOOLEAN DEFAULT true,
    deactivated_at TIMESTAMPTZ,
    
    CONSTRAINT valid_platform CHECK (platform IN ('macos', 'windows')),
    CONSTRAINT unique_device_per_license UNIQUE(license_id, device_id)
);

-- ============================================
-- AUDIT LOG TABLE
-- ============================================
CREATE TABLE license_audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    license_id UUID REFERENCES licenses(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    device_id VARCHAR(64),
    ip_address INET,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_licenses_key ON licenses(license_key);
CREATE INDEX idx_licenses_email ON licenses(email);
CREATE INDEX idx_licenses_active ON licenses(is_active, is_revoked);
CREATE INDEX idx_activations_license ON activations(license_id);
CREATE INDEX idx_activations_device ON activations(device_id);
CREATE INDEX idx_activations_active ON activations(is_active);
CREATE INDEX idx_audit_license ON license_audit_log(license_id);
CREATE INDEX idx_audit_created ON license_audit_log(created_at);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function: Validate and activate license
CREATE OR REPLACE FUNCTION validate_license(
    p_license_key VARCHAR,
    p_device_id VARCHAR,
    p_device_name VARCHAR DEFAULT NULL,
    p_platform VARCHAR DEFAULT 'macos',
    p_app_version VARCHAR DEFAULT NULL,
    p_os_version VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activation RECORD;
    v_active_count INT;
    v_result JSONB;
BEGIN
    -- Find license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    -- Check if license exists
    IF v_license IS NULL THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'invalid_key',
            'message', 'License key not found.'
        );
    END IF;
    
    -- Check if revoked
    IF v_license.is_revoked THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'revoked',
            'message', 'This license has been revoked.'
        );
    END IF;
    
    -- Check if inactive
    IF NOT v_license.is_active THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'inactive',
            'message', 'This license is not active.'
        );
    END IF;
    
    -- Check expiration
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'expired',
            'message', 'This license has expired.',
            'expired_at', v_license.expires_at
        );
    END IF;
    
    -- Check existing activation for this device
    SELECT * INTO v_activation
    FROM activations
    WHERE license_id = v_license.id AND device_id = p_device_id;
    
    IF v_activation IS NOT NULL THEN
        -- Device already activated, update last_seen
        UPDATE activations
        SET last_seen_at = NOW(),
            app_version = COALESCE(p_app_version, app_version),
            os_version = COALESCE(p_os_version, os_version),
            is_active = true,
            deactivated_at = NULL
        WHERE id = v_activation.id;
        
        -- Log
        INSERT INTO license_audit_log (license_id, action, device_id, details)
        VALUES (v_license.id, 'revalidate', p_device_id, 
            jsonb_build_object('platform', p_platform, 'app_version', p_app_version));
        
        RETURN jsonb_build_object(
            'valid', true,
            'plan', v_license.plan,
            'expires_at', v_license.expires_at,
            'activations_used', (SELECT COUNT(*) FROM activations WHERE license_id = v_license.id AND is_active),
            'activations_max', v_license.max_activations,
            'reactivated', true
        );
    END IF;
    
    -- Count active activations
    SELECT COUNT(*) INTO v_active_count
    FROM activations
    WHERE license_id = v_license.id AND is_active = true;
    
    -- Check max activations
    IF v_active_count >= v_license.max_activations THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'max_activations',
            'message', 'Maximum device activations reached. Deactivate another device first.',
            'activations_used', v_active_count,
            'activations_max', v_license.max_activations
        );
    END IF;
    
    -- Create new activation
    INSERT INTO activations (license_id, device_id, device_name, platform, app_version, os_version)
    VALUES (v_license.id, p_device_id, p_device_name, p_platform, p_app_version, p_os_version);
    
    -- Log
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'activate', p_device_id, 
        jsonb_build_object('platform', p_platform, 'device_name', p_device_name));
    
    RETURN jsonb_build_object(
        'valid', true,
        'plan', v_license.plan,
        'expires_at', v_license.expires_at,
        'activations_used', v_active_count + 1,
        'activations_max', v_license.max_activations,
        'newly_activated', true
    );
END;
$$;

-- Function: Deactivate device
CREATE OR REPLACE FUNCTION deactivate_device(
    p_license_key VARCHAR,
    p_device_id VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activation RECORD;
BEGIN
    -- Find license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    IF v_license IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'invalid_key');
    END IF;
    
    -- Find and deactivate
    UPDATE activations
    SET is_active = false, deactivated_at = NOW()
    WHERE license_id = v_license.id AND device_id = p_device_id
    RETURNING * INTO v_activation;
    
    IF v_activation IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'device_not_found');
    END IF;
    
    -- Log
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'deactivate', p_device_id, jsonb_build_object('platform', v_activation.platform));
    
    RETURN jsonb_build_object(
        'success', true,
        'activations_remaining', (SELECT COUNT(*) FROM activations WHERE license_id = v_license.id AND is_active)
    );
END;
$$;

-- Function: Get license status
CREATE OR REPLACE FUNCTION get_license_status(
    p_license_key VARCHAR,
    p_device_id VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activations JSONB;
    v_is_device_active BOOLEAN := false;
BEGIN
    -- Find license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    IF v_license IS NULL THEN
        RETURN jsonb_build_object('found', false, 'error', 'invalid_key');
    END IF;
    
    -- Get activations
    SELECT jsonb_agg(jsonb_build_object(
        'device_id', SUBSTRING(device_id, 1, 8) || '...',
        'device_name', device_name,
        'platform', platform,
        'activated_at', activated_at,
        'last_seen_at', last_seen_at,
        'is_current', (device_id = p_device_id)
    ))
    INTO v_activations
    FROM activations
    WHERE license_id = v_license.id AND is_active = true;
    
    -- Check if current device is active
    IF p_device_id IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1 FROM activations 
            WHERE license_id = v_license.id 
            AND device_id = p_device_id 
            AND is_active = true
        ) INTO v_is_device_active;
    END IF;
    
    RETURN jsonb_build_object(
        'found', true,
        'plan', v_license.plan,
        'email', v_license.email,
        'created_at', v_license.created_at,
        'expires_at', v_license.expires_at,
        'is_expired', (v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW()),
        'is_active', v_license.is_active,
        'is_revoked', v_license.is_revoked,
        'max_activations', v_license.max_activations,
        'activations', COALESCE(v_activations, '[]'::jsonb),
        'device_is_active', v_is_device_active
    );
END;
$$;

-- Function: Heartbeat (update last_seen)
CREATE OR REPLACE FUNCTION license_heartbeat(
    p_license_key VARCHAR,
    p_device_id VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_updated BOOLEAN;
BEGIN
    SELECT l.* INTO v_license
    FROM licenses l
    WHERE l.license_key = p_license_key;
    
    IF v_license IS NULL THEN
        RETURN jsonb_build_object('valid', false, 'error', 'invalid_key');
    END IF;
    
    -- Check expiration
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN jsonb_build_object('valid', false, 'error', 'expired');
    END IF;
    
    IF v_license.is_revoked THEN
        RETURN jsonb_build_object('valid', false, 'error', 'revoked');
    END IF;
    
    -- Update last_seen
    UPDATE activations
    SET last_seen_at = NOW()
    WHERE license_id = v_license.id AND device_id = p_device_id AND is_active = true;
    
    v_updated := FOUND;
    
    RETURN jsonb_build_object(
        'valid', v_updated,
        'expires_at', v_license.expires_at,
        'error', CASE WHEN NOT v_updated THEN 'device_not_activated' ELSE NULL END
    );
END;
$$;

-- Function: Generate license key
CREATE OR REPLACE FUNCTION generate_license_key()
RETURNS VARCHAR
LANGUAGE plpgsql
AS $$
DECLARE
    v_chars VARCHAR := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    v_key VARCHAR := 'ST';
    v_i INT;
    v_j INT;
BEGIN
    -- Generate 5 groups of 5 characters (first group starts with ST)
    FOR v_i IN 1..5 LOOP
        IF v_i > 1 THEN
            v_key := v_key || '-';
        END IF;
        
        -- First group already has 'ST', add 3 more chars
        -- Other groups get 5 chars
        FOR v_j IN 1..(CASE WHEN v_i = 1 THEN 3 ELSE 5 END) LOOP
            v_key := v_key || SUBSTR(v_chars, FLOOR(RANDOM() * LENGTH(v_chars) + 1)::INT, 1);
        END LOOP;
    END LOOP;
    
    RETURN v_key;
END;
$$;

-- Function: Create new license (admin)
CREATE OR REPLACE FUNCTION create_license(
    p_email VARCHAR DEFAULT NULL,
    p_customer_name VARCHAR DEFAULT NULL,
    p_plan VARCHAR DEFAULT 'pro_monthly',
    p_duration_days INT DEFAULT NULL,
    p_max_activations INT DEFAULT 2,
    p_purchase_id VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key VARCHAR;
    v_expires_at TIMESTAMPTZ;
    v_license_id UUID;
BEGIN
    -- Generate unique key
    LOOP
        v_key := generate_license_key();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM licenses WHERE license_key = v_key);
    END LOOP;
    
    -- Calculate expiration
    IF p_plan = 'lifetime' THEN
        v_expires_at := NULL;
    ELSIF p_duration_days IS NOT NULL THEN
        v_expires_at := NOW() + (p_duration_days || ' days')::INTERVAL;
    ELSIF p_plan = 'pro_monthly' THEN
        v_expires_at := NOW() + INTERVAL '30 days';
    ELSIF p_plan = 'pro_yearly' THEN
        v_expires_at := NOW() + INTERVAL '365 days';
    ELSIF p_plan = 'trial' THEN
        v_expires_at := NOW() + INTERVAL '7 days';
    END IF;
    
    -- Create license
    INSERT INTO licenses (license_key, email, customer_name, plan, expires_at, max_activations, purchase_id, notes)
    VALUES (v_key, p_email, p_customer_name, p_plan, v_expires_at, p_max_activations, p_purchase_id, p_notes)
    RETURNING id INTO v_license_id;
    
    -- Log
    INSERT INTO license_audit_log (license_id, action, details)
    VALUES (v_license_id, 'create', jsonb_build_object(
        'plan', p_plan, 'email', p_email, 'purchase_id', p_purchase_id
    ));
    
    RETURN jsonb_build_object(
        'success', true,
        'license_key', v_key,
        'plan', p_plan,
        'expires_at', v_expires_at,
        'max_activations', p_max_activations
    );
END;
$$;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE license_audit_log ENABLE ROW LEVEL SECURITY;

-- Public can only call functions (not direct table access)
-- Service role bypasses RLS for admin operations

-- ============================================
-- GRANTS
-- ============================================

-- Allow anon to call validation functions
GRANT EXECUTE ON FUNCTION validate_license TO anon;
GRANT EXECUTE ON FUNCTION deactivate_device TO anon;
GRANT EXECUTE ON FUNCTION get_license_status TO anon;
GRANT EXECUTE ON FUNCTION license_heartbeat TO anon;

-- Service role can create licenses
GRANT EXECUTE ON FUNCTION create_license TO service_role;
GRANT EXECUTE ON FUNCTION generate_license_key TO service_role;
```

---

## API Endpoints

Supabase auto-generates REST endpoints. Use these:

### Validate License (Activate)

```bash
POST https://YOUR_PROJECT.supabase.co/rest/v1/rpc/validate_license
Headers:
  apikey: YOUR_ANON_KEY
  Content-Type: application/json

Body:
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "abc123...",
  "p_device_name": "MacBook Pro",
  "p_platform": "macos",
  "p_app_version": "2026.03.29.1"
}
```

### Deactivate Device

```bash
POST https://YOUR_PROJECT.supabase.co/rest/v1/rpc/deactivate_device
Headers:
  apikey: YOUR_ANON_KEY
  Content-Type: application/json

Body:
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "abc123..."
}
```

### Get License Status

```bash
POST https://YOUR_PROJECT.supabase.co/rest/v1/rpc/get_license_status
Headers:
  apikey: YOUR_ANON_KEY
  Content-Type: application/json

Body:
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "abc123..."
}
```

### Heartbeat

```bash
POST https://YOUR_PROJECT.supabase.co/rest/v1/rpc/license_heartbeat
Headers:
  apikey: YOUR_ANON_KEY
  Content-Type: application/json

Body:
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "abc123..."
}
```

### Create License (Admin Only - use service key)

```bash
POST https://YOUR_PROJECT.supabase.co/rest/v1/rpc/create_license
Headers:
  apikey: YOUR_SERVICE_KEY
  Authorization: Bearer YOUR_SERVICE_KEY
  Content-Type: application/json

Body:
{
  "p_email": "customer@example.com",
  "p_customer_name": "John Doe",
  "p_plan": "lifetime",
  "p_max_activations": 3,
  "p_purchase_id": "stripe_pi_xxx"
}
```

---

## License Key Format

```
STXXX-XXXXX-XXXXX-XXXXX-XXXXX
││
│└── Random characters (A-Z, 2-9, excluding confusing chars)
└── Prefix: ST = SpoofTrap

Valid characters: ABCDEFGHJKLMNPQRSTUVWXYZ23456789
Excluded: 0, O, 1, I, L (to avoid confusion)

Examples:
- STPRO-K8X2M-QW4NP-7YH3J-R9V2C
- STYR7-NMQP4-2WKXH-F8D3V-JTBG6
- ST2K9-PQMX7-NVWH4-3YCDF-8RJTB
```

---

## Device ID Generation

### macOS (Swift)

```swift
import Foundation
import IOKit
import CryptoKit

func getDeviceId() -> String {
    let platformExpert = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPlatformExpertDevice")
    )
    
    guard platformExpert != 0 else {
        return fallbackDeviceId()
    }
    
    defer { IOObjectRelease(platformExpert) }
    
    guard let uuidData = IORegistryEntryCreateCFProperty(
        platformExpert,
        kIOPlatformUUIDKey as CFString,
        kCFAllocatorDefault,
        0
    )?.takeRetainedValue() as? String else {
        return fallbackDeviceId()
    }
    
    // Hash the UUID for privacy
    let hash = SHA256.hash(data: Data(uuidData.utf8))
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

private func fallbackDeviceId() -> String {
    // Fallback: use MAC address + hostname
    let hostname = Host.current().localizedName ?? "unknown"
    let data = Data(hostname.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

func getDeviceName() -> String {
    return Host.current().localizedName ?? "Mac"
}

func getOSVersion() -> String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
}
```

### Windows (C#)

```csharp
using System;
using System.Management;
using System.Security.Cryptography;
using System.Text;

public static class DeviceInfo
{
    public static string GetDeviceId()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT UUID FROM Win32_ComputerSystemProduct");
            
            foreach (var obj in searcher.Get())
            {
                var uuid = obj["UUID"]?.ToString();
                if (!string.IsNullOrEmpty(uuid) && uuid != "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
                {
                    return HashString(uuid);
                }
            }
        }
        catch { }
        
        return GetFallbackDeviceId();
    }
    
    private static string GetFallbackDeviceId()
    {
        // Fallback: Machine name + BIOS serial
        var machineName = Environment.MachineName;
        
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT SerialNumber FROM Win32_BIOS");
            
            foreach (var obj in searcher.Get())
            {
                var serial = obj["SerialNumber"]?.ToString();
                if (!string.IsNullOrEmpty(serial))
                {
                    return HashString(machineName + serial);
                }
            }
        }
        catch { }
        
        return HashString(machineName + Guid.NewGuid().ToString());
    }
    
    private static string HashString(string input)
    {
        using var sha256 = SHA256.Create();
        var bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(input));
        return BitConverter.ToString(bytes).Replace("-", "").ToLower();
    }
    
    public static string GetDeviceName()
    {
        return Environment.MachineName;
    }
    
    public static string GetOSVersion()
    {
        return Environment.OSVersion.VersionString;
    }
}
```

---

## macOS Implementation

### File: `Sources/ProFeatures/LicenseManager.swift`

```swift
import Foundation
import CryptoKit
import IOKit

// MARK: - License Models

struct LicenseValidationResponse: Codable {
    let valid: Bool
    let plan: String?
    let expiresAt: Date?
    let activationsUsed: Int?
    let activationsMax: Int?
    let error: String?
    let message: String?
    let newlyActivated: Bool?
    let reactivated: Bool?
    
    enum CodingKeys: String, CodingKey {
        case valid
        case plan
        case expiresAt = "expires_at"
        case activationsUsed = "activations_used"
        case activationsMax = "activations_max"
        case error
        case message
        case newlyActivated = "newly_activated"
        case reactivated
    }
}

struct LicenseStatusResponse: Codable {
    let found: Bool
    let plan: String?
    let email: String?
    let expiresAt: Date?
    let isExpired: Bool?
    let isActive: Bool?
    let isRevoked: Bool?
    let maxActivations: Int?
    let deviceIsActive: Bool?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case found
        case plan
        case email
        case expiresAt = "expires_at"
        case isExpired = "is_expired"
        case isActive = "is_active"
        case isRevoked = "is_revoked"
        case maxActivations = "max_activations"
        case deviceIsActive = "device_is_active"
        case error
    }
}

struct HeartbeatResponse: Codable {
    let valid: Bool
    let expiresAt: Date?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case valid
        case expiresAt = "expires_at"
        case error
    }
}

struct StoredLicense: Codable {
    var licenseKey: String
    var plan: String
    var expiresAt: Date?
    var activatedAt: Date
    var lastValidated: Date
    var deviceId: String
}

// MARK: - License Manager

@MainActor
final class LicenseManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var licenseStatus: LicenseStatus = .checking
    @Published private(set) var currentPlan: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isValidating = false
    @Published var errorMessage: String?
    
    enum LicenseStatus: Equatable {
        case checking
        case none
        case valid
        case expired
        case invalid(reason: String)
    }
    
    // MARK: - Configuration
    
    private let supabaseURL: String
    private let supabaseAnonKey: String
    private let appVersion: String
    
    private let fileManager = FileManager.default
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 3600 // 1 hour
    private let offlineGraceDays: Int = 7
    
    // MARK: - Initialization
    
    init(
        supabaseURL: String = "https://YOUR_PROJECT.supabase.co",
        supabaseAnonKey: String = "YOUR_ANON_KEY"
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        
        Task {
            await checkStoredLicense()
        }
    }
    
    deinit {
        heartbeatTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    var isPro: Bool {
        licenseStatus == .valid
    }
    
    func activate(licenseKey: String) async -> Bool {
        let cleanKey = licenseKey.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard isValidKeyFormat(cleanKey) else {
            errorMessage = "Invalid license key format."
            return false
        }
        
        isValidating = true
        errorMessage = nil
        
        defer { isValidating = false }
        
        do {
            let response = try await validateWithServer(licenseKey: cleanKey)
            
            if response.valid {
                let stored = StoredLicense(
                    licenseKey: cleanKey,
                    plan: response.plan ?? "pro",
                    expiresAt: response.expiresAt,
                    activatedAt: Date(),
                    lastValidated: Date(),
                    deviceId: getDeviceId()
                )
                try saveLicense(stored)
                
                currentPlan = response.plan
                expiresAt = response.expiresAt
                licenseStatus = .valid
                
                startHeartbeat()
                return true
            } else {
                errorMessage = response.message ?? "Activation failed."
                licenseStatus = .invalid(reason: response.error ?? "unknown")
                return false
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
            return false
        }
    }
    
    func deactivate() async -> Bool {
        guard let stored = loadStoredLicense() else { return false }
        
        isValidating = true
        defer { isValidating = false }
        
        do {
            let body: [String: Any] = [
                "p_license_key": stored.licenseKey,
                "p_device_id": getDeviceId()
            ]
            
            let _ = try await callRPC(function: "deactivate_device", body: body)
            
            clearStoredLicense()
            licenseStatus = .none
            currentPlan = nil
            expiresAt = nil
            heartbeatTimer?.invalidate()
            
            return true
        } catch {
            errorMessage = "Failed to deactivate: \(error.localizedDescription)"
            return false
        }
    }
    
    func refreshStatus() async {
        guard let stored = loadStoredLicense() else {
            licenseStatus = .none
            return
        }
        
        do {
            let body: [String: Any] = [
                "p_license_key": stored.licenseKey,
                "p_device_id": getDeviceId()
            ]
            
            let data = try await callRPC(function: "get_license_status", body: body)
            let response = try JSONDecoder.withISO8601().decode(LicenseStatusResponse.self, from: data)
            
            if response.found == true && response.deviceIsActive == true {
                if response.isExpired == true {
                    licenseStatus = .expired
                } else if response.isRevoked == true {
                    licenseStatus = .invalid(reason: "revoked")
                    clearStoredLicense()
                } else {
                    licenseStatus = .valid
                    var updated = stored
                    updated.lastValidated = Date()
                    try? saveLicense(updated)
                }
            } else {
                licenseStatus = .invalid(reason: response.error ?? "not_found")
            }
        } catch {
            // Offline - check grace period
            let daysSinceValidation = Calendar.current.dateComponents(
                [.day], from: stored.lastValidated, to: Date()
            ).day ?? 0
            
            if daysSinceValidation <= offlineGraceDays {
                // Allow offline grace
                if let expires = stored.expiresAt, expires < Date() {
                    licenseStatus = .expired
                } else {
                    licenseStatus = .valid
                }
            } else {
                licenseStatus = .invalid(reason: "offline_expired")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func checkStoredLicense() async {
        guard let stored = loadStoredLicense() else {
            licenseStatus = .none
            return
        }
        
        currentPlan = stored.plan
        expiresAt = stored.expiresAt
        
        // Quick local check first
        if let expires = stored.expiresAt, expires < Date() {
            licenseStatus = .expired
            return
        }
        
        // Validate with server
        await refreshStatus()
        
        if licenseStatus == .valid {
            startHeartbeat()
        }
    }
    
    private func validateWithServer(licenseKey: String) async throws -> LicenseValidationResponse {
        let body: [String: Any] = [
            "p_license_key": licenseKey,
            "p_device_id": getDeviceId(),
            "p_device_name": getDeviceName(),
            "p_platform": "macos",
            "p_app_version": appVersion,
            "p_os_version": getOSVersion()
        ]
        
        let data = try await callRPC(function: "validate_license", body: body)
        return try JSONDecoder.withISO8601().decode(LicenseValidationResponse.self, from: data)
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendHeartbeat()
            }
        }
    }
    
    private func sendHeartbeat() async {
        guard let stored = loadStoredLicense() else { return }
        
        do {
            let body: [String: Any] = [
                "p_license_key": stored.licenseKey,
                "p_device_id": getDeviceId()
            ]
            
            let data = try await callRPC(function: "license_heartbeat", body: body)
            let response = try JSONDecoder.withISO8601().decode(HeartbeatResponse.self, from: data)
            
            if !response.valid {
                if response.error == "expired" {
                    licenseStatus = .expired
                } else if response.error == "revoked" {
                    licenseStatus = .invalid(reason: "revoked")
                    clearStoredLicense()
                }
            } else {
                var updated = stored
                updated.lastValidated = Date()
                try? saveLicense(updated)
            }
        } catch {
            // Silently fail heartbeat, will retry
        }
    }
    
    private func callRPC(function: String, body: [String: Any]) async throws -> Data {
        let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(function)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LicenseError.serverError
        }
        
        return data
    }
    
    // MARK: - Storage
    
    private var licenseURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SpoofTrap")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("license.dat")
    }
    
    private func saveLicense(_ license: StoredLicense) throws {
        let data = try JSONEncoder().encode(license)
        // Basic obfuscation (not secure, but prevents casual inspection)
        let obfuscated = Data(data.map { $0 ^ 0x5A })
        try obfuscated.write(to: licenseURL)
    }
    
    private func loadStoredLicense() -> StoredLicense? {
        guard let obfuscated = try? Data(contentsOf: licenseURL) else { return nil }
        let data = Data(obfuscated.map { $0 ^ 0x5A })
        return try? JSONDecoder().decode(StoredLicense.self, from: data)
    }
    
    private func clearStoredLicense() {
        try? fileManager.removeItem(at: licenseURL)
    }
    
    // MARK: - Validation
    
    private func isValidKeyFormat(_ key: String) -> Bool {
        let pattern = "^ST[A-Z2-9]{3}-[A-Z2-9]{5}-[A-Z2-9]{5}-[A-Z2-9]{5}-[A-Z2-9]{5}$"
        return key.range(of: pattern, options: .regularExpression) != nil
    }
    
    // MARK: - Device Info
    
    private func getDeviceId() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        
        guard platformExpert != 0 else { return fallbackDeviceId() }
        defer { IOObjectRelease(platformExpert) }
        
        guard let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String else {
            return fallbackDeviceId()
        }
        
        let hash = SHA256.hash(data: Data(uuid.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func fallbackDeviceId() -> String {
        let hostname = Host.current().localizedName ?? UUID().uuidString
        let hash = SHA256.hash(data: Data(hostname.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func getDeviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }
    
    private func getOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

// MARK: - Errors

enum LicenseError: Error {
    case serverError
    case invalidResponse
    case networkError
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static func withISO8601() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            
            let formatters = [
                ISO8601DateFormatter(),
                {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return f
                }()
            ]
            
            for formatter in formatters {
                if let date = formatter.date(from: string) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }
}
```

---

## Windows Implementation

### Project Structure

```
SpoofTrap.Windows/
├── SpoofTrap.Windows.csproj
├── App.xaml
├── App.xaml.cs
├── MainWindow.xaml
├── MainWindow.xaml.cs
├── Services/
│   ├── LicenseService.cs
│   ├── DeviceInfoService.cs
│   └── SecureStorageService.cs
├── ViewModels/
│   ├── MainViewModel.cs
│   └── LicenseViewModel.cs
├── Views/
│   ├── ActivationWindow.xaml
│   └── ActivationWindow.xaml.cs
└── Models/
    ├── LicenseInfo.cs
    └── ApiResponses.cs
```

### Key Files

#### `Services/LicenseService.cs`

```csharp
using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace SpoofTrap.Services
{
    public class LicenseService
    {
        private readonly string _supabaseUrl;
        private readonly string _supabaseKey;
        private readonly HttpClient _httpClient;
        private readonly DeviceInfoService _deviceInfo;
        private readonly SecureStorageService _storage;
        
        public event EventHandler<LicenseStatus>? LicenseStatusChanged;
        
        public LicenseStatus CurrentStatus { get; private set; } = LicenseStatus.Checking;
        public string? CurrentPlan { get; private set; }
        public DateTime? ExpiresAt { get; private set; }
        
        public LicenseService(string supabaseUrl, string supabaseKey)
        {
            _supabaseUrl = supabaseUrl;
            _supabaseKey = supabaseKey;
            _httpClient = new HttpClient();
            _deviceInfo = new DeviceInfoService();
            _storage = new SecureStorageService();
        }
        
        public async Task<bool> ActivateAsync(string licenseKey)
        {
            var cleanKey = licenseKey.ToUpper().Trim();
            
            if (!IsValidKeyFormat(cleanKey))
                return false;
            
            var body = new
            {
                p_license_key = cleanKey,
                p_device_id = _deviceInfo.GetDeviceId(),
                p_device_name = _deviceInfo.GetDeviceName(),
                p_platform = "windows",
                p_app_version = GetAppVersion(),
                p_os_version = _deviceInfo.GetOSVersion()
            };
            
            var response = await CallRpcAsync<ValidationResponse>("validate_license", body);
            
            if (response?.Valid == true)
            {
                var stored = new StoredLicense
                {
                    LicenseKey = cleanKey,
                    Plan = response.Plan ?? "pro",
                    ExpiresAt = response.ExpiresAt,
                    ActivatedAt = DateTime.UtcNow,
                    LastValidated = DateTime.UtcNow,
                    DeviceId = _deviceInfo.GetDeviceId()
                };
                
                _storage.SaveLicense(stored);
                CurrentPlan = response.Plan;
                ExpiresAt = response.ExpiresAt;
                UpdateStatus(LicenseStatus.Valid);
                
                return true;
            }
            
            return false;
        }
        
        public async Task<bool> DeactivateAsync()
        {
            var stored = _storage.LoadLicense();
            if (stored == null) return false;
            
            var body = new
            {
                p_license_key = stored.LicenseKey,
                p_device_id = _deviceInfo.GetDeviceId()
            };
            
            await CallRpcAsync<object>("deactivate_device", body);
            
            _storage.ClearLicense();
            UpdateStatus(LicenseStatus.None);
            
            return true;
        }
        
        public async Task CheckStoredLicenseAsync()
        {
            var stored = _storage.LoadLicense();
            
            if (stored == null)
            {
                UpdateStatus(LicenseStatus.None);
                return;
            }
            
            CurrentPlan = stored.Plan;
            ExpiresAt = stored.ExpiresAt;
            
            // Quick local check
            if (stored.ExpiresAt.HasValue && stored.ExpiresAt < DateTime.UtcNow)
            {
                UpdateStatus(LicenseStatus.Expired);
                return;
            }
            
            // Validate with server
            await RefreshStatusAsync();
        }
        
        private async Task RefreshStatusAsync()
        {
            var stored = _storage.LoadLicense();
            if (stored == null)
            {
                UpdateStatus(LicenseStatus.None);
                return;
            }
            
            try
            {
                var body = new
                {
                    p_license_key = stored.LicenseKey,
                    p_device_id = _deviceInfo.GetDeviceId()
                };
                
                var response = await CallRpcAsync<StatusResponse>("get_license_status", body);
                
                if (response?.Found == true && response.DeviceIsActive == true)
                {
                    if (response.IsExpired == true)
                        UpdateStatus(LicenseStatus.Expired);
                    else if (response.IsRevoked == true)
                    {
                        _storage.ClearLicense();
                        UpdateStatus(LicenseStatus.Invalid);
                    }
                    else
                    {
                        stored.LastValidated = DateTime.UtcNow;
                        _storage.SaveLicense(stored);
                        UpdateStatus(LicenseStatus.Valid);
                    }
                }
                else
                {
                    UpdateStatus(LicenseStatus.Invalid);
                }
            }
            catch
            {
                // Offline - check grace period (7 days)
                var daysSince = (DateTime.UtcNow - stored.LastValidated).Days;
                
                if (daysSince <= 7)
                {
                    if (stored.ExpiresAt.HasValue && stored.ExpiresAt < DateTime.UtcNow)
                        UpdateStatus(LicenseStatus.Expired);
                    else
                        UpdateStatus(LicenseStatus.Valid);
                }
                else
                {
                    UpdateStatus(LicenseStatus.Invalid);
                }
            }
        }
        
        private async Task<T?> CallRpcAsync<T>(string function, object body) where T : class
        {
            var json = JsonSerializer.Serialize(body);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var request = new HttpRequestMessage(HttpMethod.Post, $"{_supabaseUrl}/rest/v1/rpc/{function}");
            request.Headers.Add("apikey", _supabaseKey);
            request.Content = content;
            
            var response = await _httpClient.SendAsync(request);
            response.EnsureSuccessStatusCode();
            
            var responseJson = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<T>(responseJson, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        
        private bool IsValidKeyFormat(string key)
        {
            return System.Text.RegularExpressions.Regex.IsMatch(
                key, 
                @"^ST[A-Z2-9]{3}-[A-Z2-9]{5}-[A-Z2-9]{5}-[A-Z2-9]{5}-[A-Z2-9]{5}$"
            );
        }
        
        private void UpdateStatus(LicenseStatus status)
        {
            CurrentStatus = status;
            LicenseStatusChanged?.Invoke(this, status);
        }
        
        private string GetAppVersion()
        {
            return System.Reflection.Assembly.GetExecutingAssembly()
                .GetName().Version?.ToString() ?? "1.0.0";
        }
    }
    
    public enum LicenseStatus
    {
        Checking,
        None,
        Valid,
        Expired,
        Invalid
    }
}
```

---

## Admin Tools

### License Generator Script (Python)

Save as `scripts/license_admin.py`:

```python
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
import requests
from datetime import datetime
from dotenv import load_dotenv

load_dotenv('.secrets/supabase.env')

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_SERVICE_KEY = os.getenv('SUPABASE_SERVICE_KEY')

headers = {
    'apikey': SUPABASE_SERVICE_KEY,
    'Authorization': f'Bearer {SUPABASE_SERVICE_KEY}',
    'Content-Type': 'application/json'
}

def create_license(email=None, name=None, plan='pro_monthly', activations=2, purchase_id=None, notes=None):
    """Create a new license key."""
    response = requests.post(
        f'{SUPABASE_URL}/rest/v1/rpc/create_license',
        headers=headers,
        json={
            'p_email': email,
            'p_customer_name': name,
            'p_plan': plan,
            'p_max_activations': activations,
            'p_purchase_id': purchase_id,
            'p_notes': notes
        }
    )
    
    if response.status_code == 200:
        result = response.json()
        print(f"\n✅ License created successfully!")
        print(f"   Key: {result['license_key']}")
        print(f"   Plan: {result['plan']}")
        print(f"   Expires: {result['expires_at'] or 'Never (Lifetime)'}")
        print(f"   Max Activations: {result['max_activations']}")
        return result
    else:
        print(f"❌ Failed to create license: {response.text}")
        return None

def list_licenses(limit=50):
    """List recent licenses."""
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers={**headers, 'Range': f'0-{limit-1}'},
        params={'order': 'created_at.desc'}
    )
    
    if response.status_code in [200, 206]:
        licenses = response.json()
        print(f"\n📋 Recent Licenses ({len(licenses)})")
        print("-" * 80)
        for lic in licenses:
            status = "🟢" if lic['is_active'] and not lic['is_revoked'] else "🔴"
            print(f"{status} {lic['license_key']} | {lic['plan']} | {lic['email'] or 'No email'}")
        return licenses
    else:
        print(f"❌ Failed to list licenses: {response.text}")
        return []

def get_license_info(license_key):
    """Get detailed info about a license."""
    response = requests.get(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=headers,
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
        print(f"Key: {lic['license_key']}")
        print(f"Email: {lic['email'] or 'Not set'}")
        print(f"Customer: {lic['customer_name'] or 'Not set'}")
        print(f"Plan: {lic['plan']}")
        print(f"Created: {lic['created_at']}")
        print(f"Expires: {lic['expires_at'] or 'Never'}")
        print(f"Max Activations: {lic['max_activations']}")
        print(f"Active: {'Yes' if lic['is_active'] else 'No'}")
        print(f"Revoked: {'Yes' if lic['is_revoked'] else 'No'}")
        
        # Get activations
        act_response = requests.get(
            f'{SUPABASE_URL}/rest/v1/activations',
            headers=headers,
            params={'license_id': f"eq.{lic['id']}", 'select': '*'}
        )
        
        if act_response.status_code == 200:
            activations = act_response.json()
            print(f"\nActivations ({len(activations)}/{lic['max_activations']}):")
            for act in activations:
                status = "🟢" if act['is_active'] else "⚪"
                print(f"  {status} {act['platform']} | {act['device_name']} | Last seen: {act['last_seen_at']}")
        
        return lic
    else:
        print(f"❌ Failed to get license: {response.text}")
        return None

def revoke_license(license_key, reason=None):
    """Revoke a license."""
    response = requests.patch(
        f'{SUPABASE_URL}/rest/v1/licenses',
        headers=headers,
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

def main():
    parser = argparse.ArgumentParser(description='SpoofTrap License Admin')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Create command
    create_parser = subparsers.add_parser('create', help='Create a new license')
    create_parser.add_argument('--email', help='Customer email')
    create_parser.add_argument('--name', help='Customer name')
    create_parser.add_argument('--plan', default='pro_monthly',
                               choices=['trial', 'pro_monthly', 'pro_yearly', 'lifetime'])
    create_parser.add_argument('--activations', type=int, default=2, help='Max activations')
    create_parser.add_argument('--purchase-id', help='External purchase ID')
    create_parser.add_argument('--notes', help='Admin notes')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List licenses')
    list_parser.add_argument('--limit', type=int, default=50)
    
    # Info command
    info_parser = subparsers.add_parser('info', help='Get license info')
    info_parser.add_argument('key', help='License key')
    
    # Revoke command
    revoke_parser = subparsers.add_parser('revoke', help='Revoke a license')
    revoke_parser.add_argument('key', help='License key')
    revoke_parser.add_argument('--reason', help='Revocation reason')
    
    args = parser.parse_args()
    
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        print("❌ Missing Supabase credentials. Set SUPABASE_URL and SUPABASE_SERVICE_KEY.")
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
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
```

---

## Security

### Best Practices

1. **Never embed service key in apps** - Only use anon key in client apps
2. **Use Row Level Security (RLS)** - Enabled in schema above
3. **Hash device IDs** - Don't store raw hardware identifiers
4. **Obfuscate stored license** - Basic XOR in example, consider encryption
5. **Certificate pinning** - Pin Supabase SSL cert in production
6. **Rate limiting** - Supabase has built-in rate limits
7. **Audit logging** - All actions logged in `license_audit_log`

### Offline Grace Period

Allow 7 days offline before requiring revalidation:
- Prevents issues with intermittent connectivity
- Still validates on app launch when online
- Balances UX with license protection

---

## Testing

### Test License Keys

Create test licenses with the admin script:

```bash
# Trial (7 days)
python scripts/license_admin.py create --plan trial --email test@example.com

# Monthly Pro
python scripts/license_admin.py create --plan pro_monthly --email test@example.com

# Lifetime
python scripts/license_admin.py create --plan lifetime --email test@example.com
```

### Test Scenarios

1. **Valid activation** - New key, first device
2. **Reactivation** - Same key, same device
3. **Multi-device** - Same key, second device
4. **Max activations** - Exceed device limit
5. **Expired license** - Use after expiration
6. **Revoked license** - Admin revoked
7. **Invalid key format** - Wrong format
8. **Offline mode** - No network, within grace
9. **Offline expired** - No network, past grace
10. **Deactivation** - Remove device

---

## Integration Checklist

### macOS

- [ ] Add `LicenseManager.swift` to project
- [ ] Update `ProManager` to use `LicenseManager`
- [ ] Add activation UI (license key input)
- [ ] Show license status in settings
- [ ] Add deactivation option
- [ ] Handle offline grace period
- [ ] Test all scenarios

### Windows

- [ ] Create Windows project structure
- [ ] Implement `LicenseService.cs`
- [ ] Implement `DeviceInfoService.cs`
- [ ] Implement `SecureStorageService.cs`
- [ ] Create activation window
- [ ] Integrate with main app
- [ ] Test all scenarios

### Backend

- [ ] Create Supabase project
- [ ] Run database migrations
- [ ] Test RPC functions
- [ ] Set up admin script
- [ ] Create test licenses
- [ ] Verify RLS policies

---

## Support

For issues with the licensing system:

1. Check `license_audit_log` table for recent actions
2. Verify device ID is consistent
3. Check network connectivity
4. Verify Supabase project status
5. Check for expired/revoked status
