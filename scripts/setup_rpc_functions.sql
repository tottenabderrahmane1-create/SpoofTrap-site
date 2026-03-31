-- ============================================
-- SPOOFTRAP LICENSE SYSTEM - RPC FUNCTIONS
-- Run this in Supabase SQL Editor AFTER setup_database.sql
-- ============================================

-- ============================================
-- 1. VALIDATE LICENSE
-- Called by client apps to check if license is valid
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
    -- Find the license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    -- License not found
    IF NOT FOUND THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'invalid_key',
            'message', 'License key not found'
        );
    END IF;
    
    -- License revoked
    IF v_license.is_revoked THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'revoked',
            'message', 'License has been revoked'
        );
    END IF;
    
    -- License inactive
    IF NOT v_license.is_active THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'inactive',
            'message', 'License is not active'
        );
    END IF;
    
    -- License expired
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'expired',
            'message', 'License has expired',
            'expired_at', v_license.expires_at
        );
    END IF;
    
    -- Check if device is already activated
    SELECT * INTO v_activation
    FROM activations
    WHERE license_id = v_license.id
      AND device_id = p_device_id
      AND is_active = true;
    
    IF FOUND THEN
        -- Update last seen
        UPDATE activations
        SET last_seen_at = NOW(),
            app_version = COALESCE(p_app_version, app_version),
            os_version = COALESCE(p_os_version, os_version)
        WHERE id = v_activation.id;
        
        RETURN json_build_object(
            'valid', true,
            'plan', v_license.plan,
            'expires_at', v_license.expires_at,
            'activation_id', v_activation.id
        );
    END IF;
    
    -- Count current activations
    SELECT COUNT(*) INTO v_activation_count
    FROM activations
    WHERE license_id = v_license.id
      AND is_active = true;
    
    -- Check if max activations reached
    IF v_activation_count >= v_license.max_activations THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'max_activations',
            'message', 'Maximum devices reached',
            'max', v_license.max_activations,
            'current', v_activation_count
        );
    END IF;
    
    -- Create new activation
    INSERT INTO activations (
        license_id, device_id, device_name, platform,
        app_version, os_version, activated_at, last_seen_at
    ) VALUES (
        v_license.id, p_device_id, p_device_name, p_platform,
        p_app_version, p_os_version, NOW(), NOW()
    )
    RETURNING * INTO v_activation;
    
    -- Log activation
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'activation', p_device_id, json_build_object(
        'device_name', p_device_name,
        'platform', p_platform,
        'app_version', p_app_version
    ));
    
    RETURN json_build_object(
        'valid', true,
        'plan', v_license.plan,
        'expires_at', v_license.expires_at,
        'activation_id', v_activation.id,
        'newly_activated', true
    );
END;
$$;

-- ============================================
-- 2. DEACTIVATE DEVICE
-- Called when user wants to free up a slot
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
    -- Find the license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'invalid_key');
    END IF;
    
    -- Find and deactivate
    UPDATE activations
    SET is_active = false, deactivated_at = NOW()
    WHERE license_id = v_license.id
      AND device_id = p_device_id
      AND is_active = true
    RETURNING * INTO v_activation;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'device_not_found');
    END IF;
    
    -- Log deactivation
    INSERT INTO license_audit_log (license_id, action, device_id, details)
    VALUES (v_license.id, 'deactivation', p_device_id, NULL);
    
    RETURN json_build_object('success', true);
END;
$$;

-- ============================================
-- 3. HEARTBEAT (for tracking active usage)
-- Called periodically by client
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
    -- Find license
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    IF NOT FOUND OR v_license.is_revoked OR NOT v_license.is_active THEN
        RETURN json_build_object('valid', false);
    END IF;
    
    -- Check expiration
    IF v_license.expires_at IS NOT NULL AND v_license.expires_at < NOW() THEN
        RETURN json_build_object('valid', false, 'expired', true);
    END IF;
    
    -- Update last seen
    UPDATE activations
    SET last_seen_at = NOW()
    WHERE license_id = v_license.id
      AND device_id = p_device_id
      AND is_active = true;
    
    RETURN json_build_object('valid', true);
END;
$$;

-- ============================================
-- 4. GET LICENSE STATUS (public info)
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
    SELECT * INTO v_license
    FROM licenses
    WHERE license_key = p_license_key;
    
    IF NOT FOUND THEN
        RETURN json_build_object('found', false);
    END IF;
    
    SELECT COUNT(*) INTO v_activation_count
    FROM activations
    WHERE license_id = v_license.id
      AND is_active = true;
    
    RETURN json_build_object(
        'found', true,
        'plan', v_license.plan,
        'is_active', v_license.is_active,
        'is_revoked', v_license.is_revoked,
        'expires_at', v_license.expires_at,
        'activations', v_activation_count,
        'max_activations', v_license.max_activations
    );
END;
$$;

-- ============================================
-- Grant execute permissions (for anon/authenticated)
-- ============================================
GRANT EXECUTE ON FUNCTION validate_license TO anon, authenticated;
GRANT EXECUTE ON FUNCTION deactivate_device TO anon, authenticated;
GRANT EXECUTE ON FUNCTION license_heartbeat TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_license_status TO anon, authenticated;

-- ============================================
-- Enable RLS but allow RPC functions to bypass
-- ============================================
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE license_audit_log ENABLE ROW LEVEL SECURITY;

-- Service role (admin) can do everything
CREATE POLICY "Service role full access on licenses" ON licenses
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on activations" ON activations
    FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on audit" ON license_audit_log
    FOR ALL USING (auth.role() = 'service_role');
