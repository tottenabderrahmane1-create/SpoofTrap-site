-- ============================================
-- SPOOFTRAP LICENSE SYSTEM - COMPLETE SETUP
-- Copy this entire file into Supabase SQL Editor and Run
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

-- ============================================
-- RPC FUNCTION: VALIDATE LICENSE
-- ============================================
CREATE OR REPLACE FUNCTION validate_license(
    p_license_key VARCHAR,
    p_device_id VARCHAR,
    p_device_name VARCHAR DEFAULT NULL,
    p_platform VARCHAR DEFAULT 'macos',
    p_app_version VARCHAR DEFAULT NULL,
    p_os_version VARCHAR DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activation RECORD;
    v_activation_count INT;
    v_result JSON;
BEGIN
    SELECT * INTO v_license FROM licenses WHERE license_key = p_license_key;
    
    IF NOT FOUND THEN
        RETURN json_build_object('valid', false, 'error', 'invalid_key', 'message', 'License key not found');
    END IF;
    
    IF v_license.is_revoked THEN
        RETURN json_build_object('valid', false, 'error', 'revoked', 'message', 'License has been revoked');
    END IF;
    
    IF NOT v_license.is_active THEN
        RETURN json_build_object('valid', false, 'error', 'inactive', 'message', 'License is not active');
    END IF;
    
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN json_build_object('valid', false, 'error', 'expired', 'message', 'License has expired', 'expired_at', v_license.expires_at);
    END IF;
    
    SELECT * INTO v_activation FROM activations
    WHERE license_id = v_license.id AND device_id = p_device_id AND is_active = true;
    
    IF FOUND THEN
        UPDATE activations SET last_seen_at = NOW(),
            app_version = COALESCE(p_app_version, app_version),
            os_version = COALESCE(p_os_version, os_version)
        WHERE id = v_activation.id;
        
        RETURN json_build_object('valid', true, 'plan', v_license.plan, 'expires_at', v_license.expires_at, 'activation_id', v_activation.id);
    END IF;
    
    SELECT COUNT(*) INTO v_activation_count FROM activations WHERE license_id = v_license.id AND is_active = true;
    
    IF v_activation_count >= v_license.max_activations THEN
        RETURN json_build_object('valid', false, 'error', 'max_activations', 'message', 'Maximum devices reached', 'max', v_license.max_activations, 'current', v_activation_count);
    END IF;
    
    INSERT INTO activations (license_id, device_id, device_name, platform, app_version, os_version, activated_at, last_seen_at)
    VALUES (v_license.id, p_device_id, p_device_name, p_platform, p_app_version, p_os_version, NOW(), NOW())
    RETURNING * INTO v_activation;
    
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'activation', p_device_id, json_build_object('device_name', p_device_name, 'platform', p_platform, 'app_version', p_app_version));
    
    RETURN json_build_object('valid', true, 'plan', v_license.plan, 'expires_at', v_license.expires_at, 'activation_id', v_activation.id, 'newly_activated', true);
END;
$$;

-- ============================================
-- RPC FUNCTION: DEACTIVATE DEVICE
-- ============================================
CREATE OR REPLACE FUNCTION deactivate_device(
    p_license_key VARCHAR,
    p_device_id VARCHAR
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activation RECORD;
BEGIN
    SELECT * INTO v_license FROM licenses WHERE license_key = p_license_key;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'invalid_key');
    END IF;
    
    UPDATE activations SET is_active = false, deactivated_at = NOW()
    WHERE license_id = v_license.id AND device_id = p_device_id AND is_active = true
    RETURNING * INTO v_activation;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'device_not_found');
    END IF;
    
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'deactivation', p_device_id, NULL);
    
    RETURN json_build_object('success', true);
END;
$$;

-- ============================================
-- RPC FUNCTION: LICENSE HEARTBEAT
-- ============================================
CREATE OR REPLACE FUNCTION license_heartbeat(
    p_license_key VARCHAR,
    p_device_id VARCHAR
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
BEGIN
    SELECT * INTO v_license FROM licenses WHERE license_key = p_license_key;
    
    IF NOT FOUND OR v_license.is_revoked OR NOT v_license.is_active THEN
        RETURN json_build_object('valid', false);
    END IF;
    
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN json_build_object('valid', false, 'expired', true);
    END IF;
    
    UPDATE activations SET last_seen_at = NOW()
    WHERE license_id = v_license.id AND device_id = p_device_id AND is_active = true;
    
    RETURN json_build_object('valid', true);
END;
$$;

-- ============================================
-- RPC FUNCTION: GET LICENSE STATUS
-- ============================================
CREATE OR REPLACE FUNCTION get_license_status(
    p_license_key VARCHAR
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license RECORD;
    v_activation_count INT;
BEGIN
    SELECT * INTO v_license FROM licenses WHERE license_key = p_license_key;
    
    IF NOT FOUND THEN
        RETURN json_build_object('found', false);
    END IF;
    
    SELECT COUNT(*) INTO v_activation_count FROM activations WHERE license_id = v_license.id AND is_active = true;
    
    RETURN json_build_object('found', true, 'plan', v_license.plan, 'is_active', v_license.is_active, 'is_revoked', v_license.is_revoked, 'expires_at', v_license.expires_at, 'activations', v_activation_count, 'max_activations', v_license.max_activations);
END;
$$;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION validate_license TO anon, authenticated;
GRANT EXECUTE ON FUNCTION deactivate_device TO anon, authenticated;
GRANT EXECUTE ON FUNCTION license_heartbeat TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_license_status TO anon, authenticated;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE license_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on licenses" ON licenses FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on activations" ON activations FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Service role full access on audit" ON license_audit_log FOR ALL USING (auth.role() = 'service_role');

-- ============================================
-- DONE! Your license system is ready.
-- ============================================
