-- ============================================
-- SPOOFTRAP LICENSE SYSTEM - DATABASE SCHEMA
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- LICENSES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS licenses (
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
CREATE TABLE IF NOT EXISTS activations (
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
CREATE TABLE IF NOT EXISTS license_audit_log (
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
CREATE INDEX IF NOT EXISTS idx_licenses_key ON licenses(license_key);
CREATE INDEX IF NOT EXISTS idx_licenses_email ON licenses(email);
CREATE INDEX IF NOT EXISTS idx_licenses_active ON licenses(is_active, is_revoked);
CREATE INDEX IF NOT EXISTS idx_activations_license ON activations(license_id);
CREATE INDEX IF NOT EXISTS idx_activations_device ON activations(device_id);
CREATE INDEX IF NOT EXISTS idx_activations_active ON activations(is_active);
CREATE INDEX IF NOT EXISTS idx_audit_license ON license_audit_log(license_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON license_audit_log(created_at);
